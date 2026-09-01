import { config } from '../config.js';
import { firebaseAdmin, getAdminFirestore } from '../firebase/firestore.js';

type CollectionScope = { name: string; collectionGroup?: boolean };

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
    const snapshot = await source.where(field, '==', value).get();
    if (snapshot.empty) return;
    const writer = this.database.bulkWriter();
    for (const document of snapshot.docs) mutate(writer, document.ref);
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
  await store.deleteStoragePrefix(avatarPrefix(firebaseUid));

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
    await store.deleteWhere({ name: collection }, 'userId', firebaseUid);
    if (collection === 'adminPointAdjustments') {
      await store.deleteWhere({ name: collection }, 'targetUserId', firebaseUid);
      // An adjustment belongs to its target user's point history. Retain that
      // history when its administrator deletes their account, but remove the
      // administrator's direct identity and display name.
      await store.anonymizeWhere(
        { name: collection },
        'adminId',
        firebaseUid,
        ['adminId', 'adminDisplayName'],
      );
    }
  }
  for (const collectionGroup of ['attempts', 'reactions', 'comments', 'taps']) {
    await store.deleteWhere(
      { name: collectionGroup, collectionGroup: true },
      'userId',
      firebaseUid,
    );
  }
  await store.deleteWhere({ name: 'usernames' }, 'uid', firebaseUid);

  for (const seasonId of await store.listDocumentIds('leaderboardSeasons')) {
    await store.deleteDocument(
      `leaderboardSeasons/${seasonId}/entries/${firebaseUid}`,
    );
  }
  await store.deleteDocument(`leaderboardEntries/${firebaseUid}`);

  await store.anonymizeWhere(
    { name: 'posts' },
    'createdBy',
    firebaseUid,
    ['createdBy'],
    { authorName: 'ABU 3MEER' },
  );
  await store.anonymizeWhere(
    { name: 'matches' },
    'createdBy',
    firebaseUid,
    ['createdBy'],
  );
  for (const collection of [
    'platformSettings',
    'leaderboardSeasons',
    'achievementDefinitions',
    'levelDefinitions',
    'loyaltyRewards',
  ]) {
    await store.anonymizeWhere(
      { name: collection },
      'updatedBy',
      firebaseUid,
      ['updatedBy'],
    );
  }
  await store.anonymizeWhere(
    { name: 'duelRooms' },
    'hostUid',
    firebaseUid,
    ['hostUid'],
    { hostName: 'Deleted User' },
  );
  await store.anonymizeWhere(
    { name: 'duelRooms' },
    'guestUid',
    firebaseUid,
    ['guestUid'],
    { guestName: 'Deleted User' },
  );
  await store.anonymizeWhere(
    { name: 'suspiciousEvents' },
    'userId',
    firebaseUid,
    ['userId'],
  );
  await store.anonymizeWhere(
    { name: 'suspiciousEvents' },
    'resolvedBy',
    firebaseUid,
    ['resolvedBy'],
  );
  for (const collection of ['pointTransactions', 'loyaltyTransactions']) {
    await store.anonymizeWhere(
      { name: collection },
      'adminId',
      firebaseUid,
      ['adminId'],
    );
  }
  for (const field of [
    'statusChangedBy',
    'pendingBy',
    'contactedBy',
    'fulfilledBy',
    'cancelledBy',
  ]) {
    await store.anonymizeWhere(
      { name: 'loyaltyRedemptions' },
      field,
      firebaseUid,
      [field],
    );
  }
  await store.anonymizeWhere(
    { name: 'adminAuditLogs' },
    'adminId',
    firebaseUid,
    ['adminId', 'adminDisplayName'],
  );
  await store.anonymizeWhere(
    { name: 'adminAuditLogs' },
    'userId',
    firebaseUid,
    ['userId', 'userEmail', 'userDisplayName', 'username'],
  );
  await store.anonymizeWhere(
    { name: 'adminAuditLogs' },
    'targetUserId',
    firebaseUid,
    ['targetUserId', 'targetDisplayName', 'targetUsername'],
  );
  await store.anonymizeWhere(
    { name: 'adminAuditLogs' },
    'targetId',
    firebaseUid,
    ['targetId'],
  );

  await store.deleteDocument(`users/${firebaseUid}`, true);
}
