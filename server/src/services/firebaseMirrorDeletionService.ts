import { config } from '../config.js';
import { firebaseAdmin, getAdminFirestore } from '../firebase/firestore.js';

type CollectionScope = { name: string; collectionGroup?: boolean };

function providerErrorCode(error: unknown): string | number | undefined {
  if (typeof error !== 'object' || error == null) return undefined;
  const candidate = error as { code?: unknown; statusCode?: unknown };
  const code = candidate.code ?? candidate.statusCode;
  return typeof code === 'string' || typeof code === 'number'
    ? code
    : undefined;
}

export function isMissingCollectionGroupIndexError(error: unknown): boolean {
  const code = providerErrorCode(error);
  const message = error instanceof Error ? error.message.toLowerCase() : '';
  return (code === 9 || code === 'failed-precondition')
    && message.includes('index');
}

export function isDefinitelyAbsentStorageTarget(error: unknown): boolean {
  const code = providerErrorCode(error);
  return code === 404
    || code === '404'
    || code === 'storage/bucket-not-found'
    || code === 'storage/object-not-found';
}

export class FirebaseMirrorDeletionError extends Error {
  constructor(
    readonly stage: string,
    readonly originalError: unknown,
  ) {
    super(`Legacy Firebase cleanup failed during ${stage}.`, {
      cause: originalError,
    });
    this.name = 'FirebaseMirrorDeletionError';
  }
}

async function runDeletionStage(
  stage: string,
  operation: () => Promise<void>,
): Promise<void> {
  try {
    await operation();
  } catch (error) {
    throw new FirebaseMirrorDeletionError(stage, error);
  }
}

export interface FirebaseMirrorDeletionStore {
  deleteDocument(path: string, recursive?: boolean): Promise<void>;
  deleteWhere(scope: CollectionScope, field: string, value: string): Promise<void>;
  anonymizeWhere(
    scope: CollectionScope,
    field: string,
    value: string,
    fieldsToDelete: string[],
    replacements?: Record<string, unknown>,
  ): Promise<void>;
  listDocumentIds(collectionPath: string): Promise<string[]>;
  deleteStoragePrefix(prefix: string): Promise<void>;
}

function avatarPrefix(firebaseUid: string): string {
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(firebaseUid)) {
    throw new Error('The authenticated Firebase UID is unsafe.');
  }
  return `avatars/${firebaseUid}/`;
}

export class AdminFirebaseMirrorDeletionStore implements FirebaseMirrorDeletionStore {
  private readonly database = getAdminFirestore();

  private async mutateWhere(
    scope: CollectionScope,
    field: string,
    value: string,
    mutate: (
      writer: firebaseAdmin.firestore.BulkWriter,
      reference: firebaseAdmin.firestore.DocumentReference,
    ) => void,
  ): Promise<void> {
    const source = scope.collectionGroup
      ? this.database.collectionGroup(scope.name)
      : this.database.collection(scope.name);
    let documents: firebaseAdmin.firestore.QueryDocumentSnapshot[];
    try {
      documents = (await source.where(field, '==', value).get()).docs;
    } catch (error) {
      if (!scope.collectionGroup || !isMissingCollectionGroupIndexError(error)) {
        throw error;
      }
      // A legacy environment may not have the collection-group field index
      // yet. A full group scan is slower but account deletion is rare, and it
      // is safer than trapping the user or skipping private mirror records.
      documents = (await source.get()).docs.filter(
        (document) => document.get(field) === value,
      );
    }
    if (documents.length === 0) return;
    const writer = this.database.bulkWriter();
    for (const document of documents) mutate(writer, document.ref);
    await writer.close();
  }

  async deleteDocument(documentPath: string, recursive = false): Promise<void> {
    const reference = this.database.doc(documentPath);
    if (recursive) await this.database.recursiveDelete(reference);
    else await reference.delete();
  }

  async deleteWhere(
    scope: CollectionScope,
    field: string,
    value: string,
  ): Promise<void> {
    await this.mutateWhere(scope, field, value, (writer, reference) => {
      writer.delete(reference);
    });
  }

  async anonymizeWhere(
    scope: CollectionScope,
    field: string,
    value: string,
    fieldsToDelete: string[],
    replacements: Record<string, unknown> = {},
  ): Promise<void> {
    const update = { ...replacements };
    for (const fieldName of fieldsToDelete) {
      update[fieldName] = firebaseAdmin.firestore.FieldValue.delete();
    }
    await this.mutateWhere(scope, field, value, (writer, reference) => {
      writer.update(reference, update);
    });
  }

  async listDocumentIds(collectionPath: string): Promise<string[]> {
    const snapshot = await this.database.collection(collectionPath).select().get();
    return snapshot.docs.map((document) => document.id);
  }

  async deleteStoragePrefix(prefix: string): Promise<void> {
    const bucketName = `${config.firebase.projectId}.firebasestorage.app`;
    await firebaseAdmin.storage().bucket(bucketName).deleteFiles({
      prefix,
      force: true,
    });
  }
}

/** Delete the legacy Firebase data mirror while leaving Firebase Auth intact.
 * Flutter deletes Auth only after this API request and PostgreSQL both succeed.
 */
export async function deleteFirebaseMirrorData(
  firebaseUid: string,
  store: FirebaseMirrorDeletionStore = new AdminFirebaseMirrorDeletionStore(),
): Promise<void> {
  const userAvatarPrefix = avatarPrefix(firebaseUid);
  await runDeletionStage('storage:avatars', async () => {
    try {
      await store.deleteStoragePrefix(userAvatarPrefix);
    } catch (error) {
      // A project with no legacy bucket (or an already-removed bucket/object)
      // has nothing left to erase. Only an explicit provider "not found" is
      // treated as clean; permission and connectivity errors still fail closed.
      if (!isDefinitelyAbsentStorageTarget(error)) throw error;
    }
  });

  for (const collection of [
    'predictions',
    'pointTransactions',
    'achievementClaims',
    'loyaltyRedemptions',
    'loyaltyTransactions',
    'loyaltyRewardClaims',
    'adminPointAdjustments',
    'securityIdempotency',
  ]) {
    await runDeletionStage(`firestore:${collection}.userId`, () =>
      store.deleteWhere({ name: collection }, 'userId', firebaseUid),
    );
    if (collection === 'adminPointAdjustments') {
      await runDeletionStage(`firestore:${collection}.targetUserId`, () =>
        store.deleteWhere({ name: collection }, 'targetUserId', firebaseUid),
      );
      // An adjustment belongs to its target user's point history. Retain that
      // history when its administrator deletes their account, but remove the
      // administrator's direct identity and display name.
      await runDeletionStage(`firestore:${collection}.adminId`, () =>
        store.anonymizeWhere(
          { name: collection },
          'adminId',
          firebaseUid,
          ['adminId', 'adminDisplayName'],
        ),
      );
    }
  }
  for (const collectionGroup of ['attempts', 'reactions', 'comments', 'taps']) {
    await runDeletionStage(`firestore-group:${collectionGroup}.userId`, () =>
      store.deleteWhere(
        { name: collectionGroup, collectionGroup: true },
        'userId',
        firebaseUid,
      ),
    );
  }
  await runDeletionStage('firestore:usernames.uid', () =>
    store.deleteWhere({ name: 'usernames' }, 'uid', firebaseUid),
  );

  let seasonIds: string[];
  try {
    seasonIds = await store.listDocumentIds('leaderboardSeasons');
  } catch (error) {
    throw new FirebaseMirrorDeletionError(
      'firestore:leaderboardSeasons.list',
      error,
    );
  }
  for (const seasonId of seasonIds) {
    await runDeletionStage('firestore:leaderboardSeasons.entries', () =>
      store.deleteDocument(
        `leaderboardSeasons/${seasonId}/entries/${firebaseUid}`,
      ),
    );
  }
  await runDeletionStage('firestore:leaderboardEntries', () =>
    store.deleteDocument(`leaderboardEntries/${firebaseUid}`),
  );

  await runDeletionStage('firestore:posts.createdBy', () =>
    store.anonymizeWhere(
      { name: 'posts' },
      'createdBy',
      firebaseUid,
      ['createdBy'],
      { authorName: 'ABU 3MEER' },
    ),
  );
  await runDeletionStage('firestore:matches.createdBy', () =>
    store.anonymizeWhere(
      { name: 'matches' },
      'createdBy',
      firebaseUid,
      ['createdBy'],
    ),
  );
  for (const collection of [
    'platformSettings',
    'leaderboardSeasons',
    'achievementDefinitions',
    'levelDefinitions',
    'loyaltyRewards',
  ]) {
    await runDeletionStage(`firestore:${collection}.updatedBy`, () =>
      store.anonymizeWhere(
        { name: collection },
        'updatedBy',
        firebaseUid,
        ['updatedBy'],
      ),
    );
  }
  await runDeletionStage('firestore:duelRooms.hostUid', () =>
    store.anonymizeWhere(
      { name: 'duelRooms' },
      'hostUid',
      firebaseUid,
      ['hostUid'],
      { hostName: 'Deleted User' },
    ),
  );
  await runDeletionStage('firestore:duelRooms.guestUid', () =>
    store.anonymizeWhere(
      { name: 'duelRooms' },
      'guestUid',
      firebaseUid,
      ['guestUid'],
      { guestName: 'Deleted User' },
    ),
  );
  await runDeletionStage('firestore:suspiciousEvents.userId', () =>
    store.anonymizeWhere(
      { name: 'suspiciousEvents' },
      'userId',
      firebaseUid,
      ['userId'],
    ),
  );
  await runDeletionStage('firestore:suspiciousEvents.resolvedBy', () =>
    store.anonymizeWhere(
      { name: 'suspiciousEvents' },
      'resolvedBy',
      firebaseUid,
      ['resolvedBy'],
    ),
  );
  for (const collection of ['pointTransactions', 'loyaltyTransactions']) {
    await runDeletionStage(`firestore:${collection}.adminId`, () =>
      store.anonymizeWhere(
        { name: collection },
        'adminId',
        firebaseUid,
        ['adminId'],
      ),
    );
  }
  for (const field of [
    'statusChangedBy',
    'pendingBy',
    'contactedBy',
    'fulfilledBy',
    'cancelledBy',
  ]) {
    await runDeletionStage(`firestore:loyaltyRedemptions.${field}`, () =>
      store.anonymizeWhere(
        { name: 'loyaltyRedemptions' },
        field,
        firebaseUid,
        [field],
      ),
    );
  }
  await runDeletionStage('firestore:adminAuditLogs.adminId', () =>
    store.anonymizeWhere(
      { name: 'adminAuditLogs' },
      'adminId',
      firebaseUid,
      ['adminId', 'adminDisplayName'],
    ),
  );
  await runDeletionStage('firestore:adminAuditLogs.userId', () =>
    store.anonymizeWhere(
      { name: 'adminAuditLogs' },
      'userId',
      firebaseUid,
      ['userId', 'userEmail', 'userDisplayName', 'username'],
    ),
  );
  await runDeletionStage('firestore:adminAuditLogs.targetUserId', () =>
    store.anonymizeWhere(
      { name: 'adminAuditLogs' },
      'targetUserId',
      firebaseUid,
      ['targetUserId', 'targetDisplayName', 'targetUsername'],
    ),
  );
  await runDeletionStage('firestore:adminAuditLogs.targetId', () =>
    store.anonymizeWhere(
      { name: 'adminAuditLogs' },
      'targetId',
      firebaseUid,
      ['targetId'],
    ),
  );

  await runDeletionStage('firestore:users', () =>
    store.deleteDocument(`users/${firebaseUid}`, true),
  );
}
