import { getClient } from '../db/pool.js';

export interface AccountDeletionClient {
  query: (
    text: string,
    params?: unknown[],
  ) => Promise<{ rowCount: number | null; rows: Array<Record<string, unknown>> }>;
  release: () => void;
}

export type AccountDeletionClientFactory = () => Promise<AccountDeletionClient>;

export async function deleteAccountData(
  userId: string,
  requestId: string,
  getDeletionClient: AccountDeletionClientFactory = getClient,
): Promise<boolean> {
  const client = await getDeletionClient();
  try {
    await client.query('BEGIN');
    const deleted = await client.query(
      `DELETE FROM users
       WHERE id = $1
       RETURNING id`,
      [userId],
    );
    if (deleted.rowCount !== 1) {
      await client.query('ROLLBACK');
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
    return true;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}
