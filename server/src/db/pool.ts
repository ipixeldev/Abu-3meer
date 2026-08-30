import pg from 'pg';
import { config } from '../config.js';

const { Pool } = pg;

export const pool = new Pool({
  connectionString: config.database.url,
  max: config.database.maxConnections,
  idleTimeoutMillis: config.database.idleTimeoutMillis,
  connectionTimeoutMillis: config.database.connectionTimeoutMillis,
});

pool.on('error', (err) => {
  console.error('[PostgreSQL] Unexpected error on idle client:', err);
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
