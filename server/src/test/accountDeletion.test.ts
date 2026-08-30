import assert from 'node:assert/strict';
import test from 'node:test';
import {
  AccountDeletionClient,
  deleteAccountData,
} from '../services/accountDeletionService.js';

function deletionClient(options: { deleteCount?: number; failAudit?: boolean } = {}) {
  const statements: string[] = [];
  let released = false;
  const client: AccountDeletionClient = {
    async query(text) {
      statements.push(text.trim());
      if (text.includes('DELETE FROM users')) {
        const rowCount = options.deleteCount ?? 1;
        return { rowCount, rows: rowCount === 1 ? [{ id: 'user-1' }] : [] };
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

test('account deletion atomically deletes the user and writes a non-identifying audit', async () => {
  const fixture = deletionClient();
  const deleted = await deleteAccountData(
    'user-1',
    'request-1',
    async () => fixture.client,
  );

  assert.equal(deleted, true);
  assert.match(fixture.statements[0], /^BEGIN$/);
  assert.match(fixture.statements[1], /DELETE FROM users/);
  assert.match(fixture.statements[2], /account_deletion_audit/);
  assert.doesNotMatch(fixture.statements[2], /user_id|firebase_uid|email/i);
  assert.match(fixture.statements[3], /^COMMIT$/);
  assert.equal(fixture.released(), true);
});

test('a missing account rolls back and never invents a successful audit', async () => {
  const fixture = deletionClient({ deleteCount: 0 });
  const deleted = await deleteAccountData(
    'missing',
    'request-2',
    async () => fixture.client,
  );

  assert.equal(deleted, false);
  assert.equal(fixture.statements.some((sql) => sql.includes('account_deletion_audit')), false);
  assert.match(fixture.statements.at(-1) ?? '', /^ROLLBACK$/);
  assert.equal(fixture.released(), true);
});

test('an audit failure rolls back the user deletion and propagates the error', async () => {
  const fixture = deletionClient({ failAudit: true });
  await assert.rejects(
    deleteAccountData('user-1', 'request-3', async () => fixture.client),
    /audit unavailable/,
  );
  assert.match(fixture.statements.at(-1) ?? '', /^ROLLBACK$/);
  assert.equal(fixture.released(), true);
});
