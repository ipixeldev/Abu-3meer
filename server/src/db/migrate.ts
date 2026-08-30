import fs from 'fs';
import path from 'path';
import pg from 'pg';
import { config } from '../config.js';

const { Pool } = pg;

async function runMigrations() {
  const migrationPool = new Pool({
    connectionString: config.database.directUrl || config.database.url,
  });

  console.log('[Migration] Connecting to database...');
  const client = await migrationPool.connect();

  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version VARCHAR(255) PRIMARY KEY,
        applied_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
      );
    `);

    const appliedRes = await client.query('SELECT version FROM schema_migrations');
    const applied = new Set(appliedRes.rows.map((r: any) => r.version));

    const migrationsDir = path.resolve(process.cwd(), 'migrations');
    if (!fs.existsSync(migrationsDir)) {
      console.log('[Migration] No migrations directory found at', migrationsDir);
      return;
    }

    const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();

    for (const file of files) {
      if (applied.has(file)) {
        console.log(`[Migration] Already applied: ${file}`);
        continue;
      }

      console.log(`[Migration] Applying migration: ${file}...`);
      const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf-8');

      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations (version) VALUES ($1)', [file]);
        await client.query('COMMIT');
        console.log(`[Migration] Successfully applied: ${file}`);
      } catch (err) {
        await client.query('ROLLBACK');
        console.error(`[Migration] Failed on ${file}:`, err);
        throw err;
      }
    }

    console.log('[Migration] All database migrations are up to date.');
  } finally {
    client.release();
    await migrationPool.end();
  }
}

if (process.argv[1]?.includes('migrate')) {
  runMigrations()
    .then(() => process.exit(0))
    .catch((err) => {
      console.error('[Migration] Migration error:', err);
      process.exit(1);
    });
}

export { runMigrations };
