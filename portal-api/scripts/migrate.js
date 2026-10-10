import pg from 'pg';
import { readdir, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL required');
const client = new pg.Client({ connectionString: process.env.DATABASE_URL, ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: true } : undefined });
await client.connect();
try {
  await client.query("select pg_advisory_lock(hashtextextended('fala-comigo-migrations',0))");
  await client.query('create table if not exists schema_migrations (name text primary key, checksum text not null, applied_at timestamptz not null default now())');
  const directory = new URL('../migrations/', import.meta.url);
  for (const file of (await readdir(directory)).filter((name) => /^\d+_.*\.sql$/.test(name)).sort()) {
    const sql = await readFile(new URL(file, directory), 'utf8');
    const checksum = createHash('sha256').update(sql).digest('hex');
    const existing = (await client.query('select checksum from schema_migrations where name=$1', [file])).rows[0];
    if (existing) { if (existing.checksum !== checksum) throw new Error(`Previously applied migration changed: ${file}`); continue; }
    await client.query('begin');
    try {
      await client.query(sql);
      await client.query('insert into schema_migrations (name,checksum) values ($1,$2)', [file,checksum]);
      await client.query('commit');
      console.log(`Applied ${file}`);
    } catch (error) { await client.query('rollback'); throw error; }
  }
} finally { await client.end(); }
