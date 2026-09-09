import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import {
  AccountDeletionClient,
  AccountDeletionFileSystem,
  deleteAccountData,
  ownedAvatarAbsolutePath,
} from '../services/accountDeletionService.js';

const userId = '11111111-1111-4111-8111-111111111111';
const avatarId = '22222222-2222-4222-8222-222222222222';

function deletionClient(options: {
  deleteCount?: number;
  failAudit?: boolean;
  storagePaths?: unknown[];
} = {}) {
  const statements: string[] = [];
  let released = false;
  const client: AccountDeletionClient = {
    async query(text) {
      statements.push(text.trim());
      if (text.includes('SELECT storage_path')) {
        return {
          rowCount: options.storagePaths?.length ?? 0,
          rows: (options.storagePaths ?? []).map((storagePath) => ({
            storage_path: storagePath,
          })),
        };
      }
      if (text.includes('DELETE FROM users')) {
        const rowCount = options.deleteCount ?? 1;
        return { rowCount, rows: rowCount === 1 ? [{ id: userId }] : [] };
      }
      if (options.failAudit && text.includes('account_deletion_audit')) {
        throw new Error('audit unavailable');
      }
      return { rowCount: null, rows: [] };
    },
    release() {
      released = true;
    },
  };
  return { client, statements, released: () => released };
}

function deletionFileSystem(options: {
  missingSources?: string[];
  failingSources?: string[];
} = {}) {
  const operations: Array<{ type: string; from?: string; to?: string; path?: string }> = [];
  const missingSources = new Set(options.missingSources ?? []);
  const failingSources = new Set(options.failingSources ?? []);
  const fileSystem: AccountDeletionFileSystem = {
    async mkdir(directory) {
      operations.push({ type: 'mkdir', path: directory });
    },
    async rename(from, to) {
      operations.push({ type: 'rename', from, to });
      if (missingSources.has(from)) {
        throw Object.assign(new Error('missing'), { code: 'ENOENT' });
      }
      if (failingSources.has(from)) {
        throw Object.assign(new Error('rename denied'), { code: 'EACCES' });
      }
    },
    async rm(target) {
      operations.push({ type: 'rm', path: target });
    },
  };
  return { fileSystem, operations };
}

test('avatar path resolution accepts only the exact owned upload subtree', () => {
  const root = '/srv/abu3meer/uploads';
  assert.equal(
    ownedAvatarAbsolutePath(root, userId, `avatar/${userId}/${avatarId}.png`),
    path.resolve(root, 'avatar', userId, `${avatarId}.png`),
  );
  assert.equal(
    ownedAvatarAbsolutePath(root, userId, `avatar/${userId}/../../admin/secret.png`),
    null,
  );
  assert.equal(
    ownedAvatarAbsolutePath(root, userId, `announcement/${userId}/${avatarId}.png`),
    null,
  );
  assert.equal(
    ownedAvatarAbsolutePath(
      root,
      userId,
      `avatar/33333333-3333-4333-8333-333333333333/${avatarId}.png`,
    ),
    null,
  );
});

test('account deletion atomically deletes the user and writes a non-identifying audit', async () => {
  const fixture = deletionClient();
  const deleted = await deleteAccountData(
    userId,
    'request-1',
    async () => fixture.client,
  );

  assert.equal(deleted, true);
  assert.match(fixture.statements[0], /^BEGIN$/);
  assert.match(fixture.statements[1], /SELECT storage_path/);
  assert.match(fixture.statements[2], /DELETE FROM media_uploads/);
  assert.match(fixture.statements[3], /DELETE FROM users/);
  assert.match(fixture.statements[4], /account_deletion_audit/);
  assert.doesNotMatch(fixture.statements[4], /user_id|firebase_uid|email/i);
  assert.match(fixture.statements[5], /^COMMIT$/);
  assert.equal(fixture.released(), true);
});

test('account deletion quarantines only owned avatars and never shared admin media', async () => {
  const root = '/srv/abu3meer/uploads';
  const validAvatar = `avatar/${userId}/${avatarId}.webp`;
  const fixture = deletionClient({
    storagePaths: [
      validAvatar,
      `challenge/${userId}/${avatarId}.webp`,
      `avatar/${userId}/../../admin/private.webp`,
    ],
  });
  const disk = deletionFileSystem();

  const deleted = await deleteAccountData(
    userId,
    'untrusted/request/id',
    async () => fixture.client,
    {
      uploadsDirectory: root,
      fileSystem: disk.fileSystem,
      deletionToken: 'safe-token',
    },
  );

  assert.equal(deleted, true);
  const renames = disk.operations.filter((operation) => operation.type === 'rename');
  assert.equal(renames.length, 1);
  assert.equal(renames[0].from, path.resolve(root, validAvatar));
  assert.equal(
    renames[0].to,
    path.resolve(root, '.account-deletions', 'safe-token', `${avatarId}.webp`),
  );
  assert.equal(
    disk.operations.some((operation) => operation.path?.includes('admin/private')),
    false,
  );
  assert.equal(
    disk.operations.some(
      (operation) =>
        operation.type === 'rm' &&
        operation.path === path.resolve(root, '.account-deletions', 'safe-token'),
    ),
    true,
  );
});

test('a missing account rolls back and never invents a successful audit', async () => {
  const fixture = deletionClient({ deleteCount: 0 });
  const deleted = await deleteAccountData(
    userId,
    'request-2',
    async () => fixture.client,
  );

  assert.equal(deleted, false);
  assert.equal(fixture.statements.some((sql) => sql.includes('account_deletion_audit')), false);
  assert.match(fixture.statements.at(-1) ?? '', /^ROLLBACK$/);
  assert.equal(fixture.released(), true);
});

test('an audit failure rolls back the user deletion and propagates the error', async () => {
  const fixture = deletionClient({
    failAudit: true,
    storagePaths: [`avatar/${userId}/${avatarId}.jpg`],
  });
  const disk = deletionFileSystem();
  await assert.rejects(
    deleteAccountData(userId, 'request-3', async () => fixture.client, {
      uploadsDirectory: '/srv/abu3meer/uploads',
      fileSystem: disk.fileSystem,
      deletionToken: 'rollback-token',
    }),
    /audit unavailable/,
  );
  assert.match(fixture.statements.at(-1) ?? '', /^ROLLBACK$/);
  const renames = disk.operations.filter((operation) => operation.type === 'rename');
  assert.equal(renames.length, 2);
  assert.equal(renames[1].from, renames[0].to);
  assert.equal(renames[1].to, renames[0].from);
  assert.equal(fixture.released(), true);
});

test('a later avatar staging failure restores avatars already quarantined', async () => {
  const root = '/srv/abu3meer/uploads';
  const firstAvatarId = avatarId;
  const secondAvatarId = '33333333-3333-4333-8333-333333333333';
  const firstAvatar = path.resolve(
    root,
    'avatar',
    userId,
    `${firstAvatarId}.png`,
  );
  const secondAvatar = path.resolve(
    root,
    'avatar',
    userId,
    `${secondAvatarId}.png`,
  );
  const fixture = deletionClient({
    storagePaths: [
      `avatar/${userId}/${firstAvatarId}.png`,
      `avatar/${userId}/${secondAvatarId}.png`,
    ],
  });
  const disk = deletionFileSystem({ failingSources: [secondAvatar] });

  await assert.rejects(
    deleteAccountData(userId, 'request-4', async () => fixture.client, {
      uploadsDirectory: root,
      fileSystem: disk.fileSystem,
      deletionToken: 'partial-stage-rollback',
    }),
    /rename denied/,
  );

  const renames = disk.operations.filter((operation) => operation.type === 'rename');
  assert.equal(renames.length, 3);
  assert.equal(renames[0].from, firstAvatar);
  assert.equal(renames[1].from, secondAvatar);
  assert.equal(renames[2].from, renames[0].to);
  assert.equal(renames[2].to, firstAvatar);
  assert.equal(
    fixture.statements.some((statement) => statement.includes('DELETE FROM users')),
    false,
  );
  assert.match(fixture.statements.at(-1) ?? '', /^ROLLBACK$/);
  assert.equal(fixture.released(), true);
});
