import assert from 'node:assert/strict';
import test from 'node:test';
import {
  FirebaseMirrorDeletionStore,
  deleteFirebaseMirrorData,
} from '../services/firebaseMirrorDeletionService.js';

test('self-hosted deletion purges the Firebase mirror without removing shared content', async () => {
  const operations: string[] = [];
  const anonymizations: Array<{
    collection: string;
    field: string;
    value: string;
    fieldsToDelete: string[];
  }> = [];
  const store: FirebaseMirrorDeletionStore = {
    async deleteDocument(path, recursive = false) {
      operations.push(`document:${path}:${recursive}`);
    },
    async deleteWhere(scope, field, value) {
      operations.push(
        `delete:${scope.collectionGroup ? 'group:' : ''}${scope.name}:${field}:${value}`,
      );
    },
    async anonymizeWhere(scope, field, value, fieldsToDelete) {
      operations.push(`anonymize:${scope.name}:${field}:${value}`);
      anonymizations.push({
        collection: scope.name,
        field,
        value,
        fieldsToDelete,
      });
    },
    async listDocumentIds(path) {
      operations.push(`list:${path}`);
      return ['2026-27'];
    },
    async deleteStoragePrefix(prefix) {
      operations.push(`storage:${prefix}`);
    },
  };

  const uid = 'firebase_user-1';
  await deleteFirebaseMirrorData(uid, store);

  assert.equal(operations[0], `storage:avatars/${uid}/`);
  assert.equal(operations.includes(`delete:predictions:userId:${uid}`), true);
  assert.equal(operations.includes(`delete:group:attempts:userId:${uid}`), true);
  assert.equal(operations.includes(`delete:group:comments:userId:${uid}`), true);
  assert.equal(
    operations.includes(`document:leaderboardSeasons/2026-27/entries/${uid}:false`),
    true,
  );
  assert.equal(operations.includes(`anonymize:posts:createdBy:${uid}`), true);
  assert.equal(operations.includes(`anonymize:duelRooms:hostUid:${uid}`), true);
  const wasAnonymized = (
    collection: string,
    field: string,
    fieldsToDelete: string[] = [field],
  ) => anonymizations.some(
    (operation) =>
      operation.collection === collection &&
      operation.field === field &&
      operation.value === uid &&
      fieldsToDelete.every((deletedField) =>
        operation.fieldsToDelete.includes(deletedField),
      ),
  );
  for (const collection of [
    'platformSettings',
    'leaderboardSeasons',
    'achievementDefinitions',
    'levelDefinitions',
    'loyaltyRewards',
  ]) {
    assert.equal(
      wasAnonymized(collection, 'updatedBy'),
      true,
      `${collection}.updatedBy was not anonymized`,
    );
  }
  assert.equal(wasAnonymized('suspiciousEvents', 'resolvedBy'), true);
  assert.equal(wasAnonymized('pointTransactions', 'adminId'), true);
  assert.equal(wasAnonymized('loyaltyTransactions', 'adminId'), true);
  for (const field of [
    'statusChangedBy',
    'pendingBy',
    'contactedBy',
    'fulfilledBy',
    'cancelledBy',
  ]) {
    assert.equal(
      wasAnonymized('loyaltyRedemptions', field),
      true,
      `loyaltyRedemptions.${field} was not anonymized`,
    );
  }
  assert.equal(
    wasAnonymized(
      'adminPointAdjustments',
      'adminId',
      ['adminId', 'adminDisplayName'],
    ),
    true,
  );
  assert.equal(
    operations.includes(`delete:adminPointAdjustments:adminId:${uid}`),
    false,
  );
  assert.equal(operations.at(-1), `document:users/${uid}:true`);
  assert.equal(operations.some((operation) => operation.startsWith('storage:admin/')), false);
  assert.equal(
    operations.some((operation) => operation.startsWith('document:posts/')),
    false,
  );
});

test('unsafe Firebase UIDs fail before any storage or database mutation', async () => {
  const operations: string[] = [];
  const store: FirebaseMirrorDeletionStore = {
    async deleteDocument() { operations.push('document'); },
    async deleteWhere() { operations.push('delete'); },
    async anonymizeWhere() { operations.push('anonymize'); },
    async listDocumentIds() { operations.push('list'); return []; },
    async deleteStoragePrefix() { operations.push('storage'); },
  };
  await assert.rejects(deleteFirebaseMirrorData('../admin', store), /unsafe/);
  assert.deepEqual(operations, []);
});
