import pg from 'pg';
import { config } from '../config.js';

const { Pool } = pg;

export const pool = new Pool({
  connectionString: config.database.url,
  max: config.database.maxConnections,
  idleTimeoutMillis: config.database.idleTimeoutMillis,
  connectionTimeoutMillis: config.database.connectionTimeoutMillis,
});

// PgBouncer runs in transaction-pooling mode in production, so session-level
// PostgreSQL state (for example advisory locks) must never use DATABASE_URL.
// Keep a deliberately small direct pool for the few operations that require a
// stable backend session for their entire lifetime.
export const directPool = new Pool({
  connectionString: config.database.directUrl,
  max: Math.min(4, config.database.maxConnections),
  idleTimeoutMillis: config.database.idleTimeoutMillis,
  connectionTimeoutMillis: config.database.connectionTimeoutMillis,
});

pool.on('error', (err) => {
  console.error('[PostgreSQL] Unexpected error on idle client:', err);
});

directPool.on('error', (err) => {
  console.error('[PostgreSQL Direct] Unexpected error on idle client:', err);
});

export async function query<T extends pg.QueryResultRow = any>(
  text: string,
  params?: any[]
): Promise<pg.QueryResult<T>> {
  const start = Date.now();
  const res = await pool.query<T>(text, params);
  const duration = Date.now() - start;
  if (duration > 500) {
    console.warn(`[PostgreSQL Slow Query] ${duration}ms: ${text.slice(0, 100)}`);
  }
  return res;
}

export async function getClient() {
  return await pool.connect();
}

export async function getDirectClient() {
  return await directPool.connect();
}

export async function closeDatabasePools() {
  await Promise.all([pool.end(), directPool.end()]);
}
