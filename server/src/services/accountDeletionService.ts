import crypto from 'crypto';
import fs from 'fs/promises';
import path from 'path';
import { config } from '../config.js';
import { getClient } from '../db/pool.js';

export interface AccountDeletionClient {
  query: (
    text: string,
    params?: unknown[],
  ) => Promise<{ rowCount: number | null; rows: Array<Record<string, unknown>> }>;
  release: () => void;
}

export type AccountDeletionClientFactory = () => Promise<AccountDeletionClient>;

export interface AccountDeletionFileSystem {
  mkdir: (path: string, options: { recursive: true }) => Promise<unknown>;
  rename: (oldPath: string, newPath: string) => Promise<void>;
  rm: (
    path: string,
    options: { recursive: true; force: true },
  ) => Promise<void>;
}

export interface AccountDeletionOptions {
  uploadsDirectory?: string;
  fileSystem?: AccountDeletionFileSystem;
  deletionToken?: string;
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const avatarFilePattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|png|webp|gif)$/i;

/**
 * Resolve a database-backed avatar path only when it belongs to the account
 * being deleted and remains below the configured upload root. A corrupted
 * storage_path must never turn account deletion into an arbitrary file delete.
 */
export function ownedAvatarAbsolutePath(
  uploadsDirectory: string,
  userId: string,
  storagePath: unknown,
): string | null {
  if (!uuidPattern.test(userId) || typeof storagePath !== 'string') return null;
  const normalized = storagePath.replace(/\\/g, '/');
  const parts = normalized.split('/');
  if (
    parts.length !== 3 ||
    parts[0] !== 'avatar' ||
    parts[1].toLowerCase() !== userId.toLowerCase() ||
    !avatarFilePattern.test(parts[2])
  ) {
    return null;
  }

  const root = path.resolve(uploadsDirectory);
  const absolutePath = path.resolve(root, ...parts);
  return absolutePath.startsWith(`${root}${path.sep}`) ? absolutePath : null;
}

type StagedAvatar = { originalPath: string; stagedPath: string };

async function stageOwnedAvatars(params: {
  uploadsDirectory: string;
  userId: string;
  storagePaths: unknown[];
  deletionToken: string;
  fileSystem: AccountDeletionFileSystem;
}): Promise<{ staged: StagedAvatar[]; stagingRoot: string }> {
  const uploadsRoot = path.resolve(params.uploadsDirectory);
  const stagingRoot = path.resolve(
    uploadsRoot,
    '.account-deletions',
    params.deletionToken,
  );
  if (!stagingRoot.startsWith(`${uploadsRoot}${path.sep}`)) {
    throw new Error('Unsafe account deletion staging path.');
  }

  const staged: StagedAvatar[] = [];
  try {
    for (const storagePath of params.storagePaths) {
      const originalPath = ownedAvatarAbsolutePath(
        params.uploadsDirectory,
        params.userId,
        storagePath,
      );
      if (!originalPath) continue;
      const stagedPath = path.join(stagingRoot, path.basename(originalPath));
      await params.fileSystem.mkdir(path.dirname(stagedPath), { recursive: true });
      try {
        await params.fileSystem.rename(originalPath, stagedPath);
        staged.push({ originalPath, stagedPath });
      } catch (error: any) {
        // A missing file is already privacy-safe and must not prevent account
        // deletion. Permission and filesystem failures remain actionable.
        if (error?.code !== 'ENOENT') throw error;
      }
    }
  } catch (error) {
    // If staging avatar N fails, avatars 1..N-1 have already moved out of
    // their public paths. Restore them here because the caller has not yet
    // received (and therefore cannot know about) the partial staged list.
    try {
      await restoreStagedAvatars(staged, params.fileSystem);
    } catch (restoreError) {
      throw new AggregateError(
        [error, restoreError],
        'Avatar staging failed and rollback could not restore every file.',
      );
    }
    throw error;
  }
  return { staged, stagingRoot };
}

async function restoreStagedAvatars(
  staged: StagedAvatar[],
  fileSystem: AccountDeletionFileSystem,
): Promise<void> {
  for (const item of [...staged].reverse()) {
    await fileSystem.mkdir(path.dirname(item.originalPath), { recursive: true });
    await fileSystem.rename(item.stagedPath, item.originalPath);
  }
}

export async function deleteAccountData(
  userId: string,
  requestId: string,
  getDeletionClient: AccountDeletionClientFactory = getClient,
  options: AccountDeletionOptions = {},
): Promise<boolean> {
  const client = await getDeletionClient();
  const fileSystem = options.fileSystem ?? fs;
  const uploadsDirectory = options.uploadsDirectory ?? config.uploads.directory;
  // Never derive a filesystem component from a request ID supplied by a
  // proxy/client. The random token also prevents concurrent deletions from
  // sharing a quarantine directory.
  const deletionToken = options.deletionToken ?? crypto.randomUUID();
  if (!/^[a-z0-9-]{1,64}$/i.test(deletionToken)) {
    throw new Error('Unsafe account deletion token.');
  }
  let stagedAvatars: StagedAvatar[] = [];
  let stagingRoot: string | null = null;
  let committed = false;
  try {
    await client.query('BEGIN');
    const avatarUploads = await client.query(
      `SELECT storage_path
       FROM media_uploads
       WHERE user_id = $1 AND purpose = 'avatar'
       FOR UPDATE`,
      [userId],
    );
    const staged = await stageOwnedAvatars({
      uploadsDirectory,
      userId,
      storagePaths: avatarUploads.rows.map((row) => row.storage_path),
      deletionToken,
      fileSystem,
    });
    stagedAvatars = staged.staged;
    stagingRoot = staged.stagingRoot;

    // Avatar metadata is private account data. Other upload purposes can be
    // shared app/admin content and are deliberately retained with a NULL
    // creator after migration 029 applies ON DELETE SET NULL.
    await client.query(
      `DELETE FROM media_uploads
       WHERE user_id = $1 AND purpose = 'avatar'`,
      [userId],
    );
    const deleted = await client.query(
      `DELETE FROM users
       WHERE id = $1
       RETURNING id`,
      [userId],
    );
    if (deleted.rowCount !== 1) {
      await client.query('ROLLBACK');
      await restoreStagedAvatars(stagedAvatars, fileSystem);
      return false;
    }

    // The audit entry deliberately contains no user ID or profile data. The
    // request ID can be correlated with short-lived server logs when needed,
    // while the deleted account itself cannot be reconstructed from this row.
    await client.query(
      `INSERT INTO account_deletion_audit (request_id)
       VALUES ($1)`,
      [requestId],
    );
    await client.query('COMMIT');
    committed = true;
    if (stagingRoot) {
      // The quarantine is outside the public upload route. Failure to remove
      // it cannot expose the avatar again, and a later maintenance sweep may
      // safely remove stale quarantine directories.
      await fileSystem
        .rm(stagingRoot, { recursive: true, force: true })
        .catch(() => undefined);
    }
    return true;
  } catch (error) {
    if (!committed) {
      await client.query('ROLLBACK').catch(() => undefined);
      if (stagedAvatars.length > 0) {
        await restoreStagedAvatars(stagedAvatars, fileSystem).catch(() => undefined);
      }
    }
    throw error;
  } finally {
    client.release();
  }
}
