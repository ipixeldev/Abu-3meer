import assert from 'node:assert/strict';
import test from 'node:test';
import {
  FirebaseMirrorDeletionError,
  FirebaseMirrorDeletionStore,
  deleteFirebaseMirrorData,
  isDefinitelyAbsentStorageTarget,
  isMissingCollectionGroupIndexError,
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

test('cleanup failures identify the exact safe stage without exposing the UID', async () => {
  const store: FirebaseMirrorDeletionStore = {
    async deleteDocument() {},
    async deleteWhere(scope) {
      if (scope.name === 'attempts') {
        throw Object.assign(new Error('missing collection-group index'), {
          code: 9,
        });
      }
    },
    async anonymizeWhere() {},
    async listDocumentIds() { return []; },
    async deleteStoragePrefix() {},
  };

  const uid = 'private_firebase_uid';
  await assert.rejects(
    deleteFirebaseMirrorData(uid, store),
    (error: unknown) => {
      assert.equal(error instanceof FirebaseMirrorDeletionError, true);
      const staged = error as FirebaseMirrorDeletionError;
      assert.equal(staged.stage, 'firestore-group:attempts.userId');
      assert.equal(staged.message.includes(uid), false);
      return true;
    },
  );
});

test('a definitively absent legacy Storage target is already clean', async () => {
  const operations: string[] = [];
  const store: FirebaseMirrorDeletionStore = {
    async deleteDocument(path) { operations.push(`document:${path}`); },
    async deleteWhere(scope) { operations.push(`delete:${scope.name}`); },
    async anonymizeWhere(scope) { operations.push(`anonymize:${scope.name}`); },
    async listDocumentIds() { return []; },
    async deleteStoragePrefix() {
      throw Object.assign(new Error('The specified bucket does not exist.'), {
        code: 404,
      });
    },
  };

  await deleteFirebaseMirrorData('firebase_user-2', store);
  assert.equal(operations.includes('delete:predictions'), true);
  assert.equal(operations.at(-1), 'document:users/firebase_user-2');
});

test('only definitive missing resources and missing-index errors use fallbacks', () => {
  assert.equal(isDefinitelyAbsentStorageTarget({ code: 404 }), true);
  assert.equal(isDefinitelyAbsentStorageTarget({ statusCode: '404' }), true);
  assert.equal(isDefinitelyAbsentStorageTarget({ code: 403 }), false);
  assert.equal(
    isMissingCollectionGroupIndexError(
      Object.assign(new Error('The query requires an index.'), { code: 9 }),
    ),
    true,
  );
  assert.equal(
    isMissingCollectionGroupIndexError(
      Object.assign(new Error('Permission denied.'), { code: 7 }),
    ),
    false,
  );
});
