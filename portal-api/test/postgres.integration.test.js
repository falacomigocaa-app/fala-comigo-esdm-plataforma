import test from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';

const connectionString = process.env.PGTEST_URL;

test('PostgreSQL migration exposes Gate 3A authorization tables and tenant constraints', { skip: !connectionString }, async () => {
  const client = new pg.Client({ connectionString });
  await client.connect();
  try {
    const tables = await client.query(`
      select table_name
      from information_schema.tables
      where table_schema = 'public'
        and table_name = any($1::text[])
      order by table_name
    `, [[
      'users', 'organizations', 'memberships', 'child_subjects', 'consents', 'invitations', 'care_relationships',
      'access_grants', 'benefit_entitlements', 'audit_events', 'esdm_goals', 'school_collections'
    ]]);
    assert.deepEqual(tables.rows.map((row) => row.table_name), [
      'access_grants', 'audit_events', 'benefit_entitlements', 'care_relationships', 'child_subjects', 'consents', 'esdm_goals',
      'invitations', 'memberships', 'organizations', 'school_collections', 'users'
    ]);

    const e2eeColumns = await client.query(`
      select column_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'school_collections'
        and column_name = any($1::text[])
      order by column_name
    `, [['organization_id', 'encrypted_data', 'iv']]);
    assert.deepEqual(e2eeColumns.rows.map((row) => row.column_name), ['encrypted_data', 'iv', 'organization_id']);

    await client.query('begin');
    await client.query(`insert into users (id, external_subject, status) values
      ('pg-user-alpha', 'synthetic:pg-alpha', 'active'),
      ('pg-user-beta', 'synthetic:pg-beta', 'active')`);
    await client.query(`insert into organizations (id, name, type, status) values
      ('pg-org-alpha', 'PG Demo Alpha', 'clinic', 'active'),
      ('pg-org-beta', 'PG Demo Beta', 'school', 'active')`);
    await client.query(`insert into memberships (id, user_id, organization_id, role, status, valid_until) values
      ('pg-membership-alpha', 'pg-user-alpha', 'pg-org-alpha', 'owner', 'active', '2099-01-01T00:00:00Z'),
      ('pg-membership-beta', 'pg-user-beta', 'pg-org-beta', 'owner', 'active', '2099-01-01T00:00:00Z')`);

    await client.query(`insert into child_subjects (id, family_space_id, owner_user_id, display_name, status)
      values ('pg-subject-alpha', 'pg-family-alpha', 'pg-user-alpha', 'PG Demo Child', 'active')`);

    const encryptedData = Buffer.from('pg-encrypted-clinical-payload').toString('base64');
    const iv = Buffer.alloc(12, 9).toString('base64');
    await client.query(`
      insert into school_collections (id, subject_id, organization_id, encrypted_data, iv, data_registro, created_by_user_id)
      values ('pg-collection-e2ee', 'pg-subject-alpha', 'pg-org-alpha', $1, $2, '2026-10-06T00:00:00Z', 'pg-user-alpha')
    `, [encryptedData, iv]);
    const persistedEnvelope = await client.query(`
      select organization_id, encrypted_data, iv, bloco_rotina_escolar, nivel_suporte
      from school_collections where id = 'pg-collection-e2ee'
    `);
    assert.deepEqual(persistedEnvelope.rows[0], {
      organization_id: 'pg-org-alpha',
      encrypted_data: encryptedData,
      iv,
      bloco_rotina_escolar: null,
      nivel_suporte: null
    });

    const isolated = await client.query(`
      select count(*)::int as count
      from memberships
      where user_id = 'pg-user-alpha' and organization_id = 'pg-org-beta'
    `);
    assert.equal(isolated.rows[0].count, 0);
    await client.query('rollback');
  } finally {
    await client.end();
  }
});
