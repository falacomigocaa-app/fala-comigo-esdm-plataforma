import test from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import { createStore } from '../src/store.js';
import { decryptOrganizationKey, encryptOrganizationKey } from '../src/services/organization-key.service.js';

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
      'access_grants', 'benefit_entitlements', 'audit_events', 'esdm_goals', 'school_collections', 'organization_keys'
    ]]);
    assert.deepEqual(tables.rows.map((row) => row.table_name), [
      'access_grants', 'audit_events', 'benefit_entitlements', 'care_relationships', 'child_subjects', 'consents', 'esdm_goals',
      'invitations', 'memberships', 'organization_keys', 'organizations', 'school_collections', 'users'
    ]);

    const keyColumns = await client.query(`
      select column_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'organization_keys'
        and column_name = any($1::text[])
      order by column_name
    `, [['organization_id', 'key_encrypted', 'key_version', 'created_by_user_id', 'rotated_by_user_id', 'created_at', 'rotated_at']]);
    assert.deepEqual(keyColumns.rows.map((row) => row.column_name), [
      'created_at', 'created_by_user_id', 'key_encrypted', 'key_version', 'organization_id', 'rotated_at', 'rotated_by_user_id'
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

    const membershipScopes = await client.query(`
      select column_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'memberships'
        and column_name = 'scopes'
    `);
    assert.equal(membershipScopes.rows.length, 1);

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

    const previousMasterKey = process.env.MASTER_CRYPTO_KEY;
    process.env.MASTER_CRYPTO_KEY = Buffer.alloc(32, 23).toString('base64');
    const rawOrganizationKey = Buffer.alloc(32, 71);
    const encryptedOrganizationKey = encryptOrganizationKey(rawOrganizationKey, { organizationId: 'pg-org-alpha', now: new Date('2026-10-06T00:00:00Z') });
    await client.query(`
      insert into organization_keys (organization_id, key_encrypted, key_version, created_by_user_id, rotated_by_user_id)
      values ('pg-org-alpha', $1, 1, 'pg-user-alpha', 'pg-user-alpha')
    `, [encryptedOrganizationKey]);
    const persistedOrganizationKey = await client.query(`
      select key_encrypted from organization_keys where organization_id = 'pg-org-alpha'
    `);
    assert.equal(persistedOrganizationKey.rows[0].key_encrypted, encryptedOrganizationKey);
    assert.deepEqual(decryptOrganizationKey(persistedOrganizationKey.rows[0].key_encrypted, { organizationId: 'pg-org-alpha' }), rawOrganizationKey);

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

    const store = createStore({ pool: client });
    const loadedKey = await store.getOrganizationKey('pg-org-alpha');
    assert.equal(loadedKey.organizationKey, rawOrganizationKey.toString('base64'));
    await store.saveCollection({ subjectId: 'pg-subject-alpha', organizationId: 'pg-org-beta', encryptedData, iv, dataRegistro: '2026-10-06T00:00:00Z', createdByUserId: 'pg-user-beta' });
    const alphaHistory = await store.getCollectionsBySubject('pg-subject-alpha', 'pg-org-alpha');
    const betaHistory = await store.getCollectionsBySubject('pg-subject-alpha', 'pg-org-beta');
    assert.equal(alphaHistory.length, 1);
    assert.equal(betaHistory.length, 1);
    assert.equal(alphaHistory[0].organizationId, 'pg-org-alpha');
    assert.equal(betaHistory[0].organizationId, 'pg-org-beta');
    const refreshClaims = { userId: 'pg-user-alpha', organizationId: 'pg-org-alpha', scopes: ['organization.read', 'access.invite'] };
    assert.deepEqual((await store.validateRefreshClaims(refreshClaims)).scopes, refreshClaims.scopes);
    await client.query("update memberships set role = 'professional' where id = 'pg-membership-alpha'");
    assert.deepEqual((await store.validateRefreshClaims(refreshClaims)).scopes, ['organization.read']);
    await client.query("update memberships set status = 'revoked' where id = 'pg-membership-alpha'");
    await assert.rejects(() => store.validateRefreshClaims(refreshClaims), (error) => error.code === 'REFRESH_TOKEN_INVALID');

    if (previousMasterKey === undefined) delete process.env.MASTER_CRYPTO_KEY;
    else process.env.MASTER_CRYPTO_KEY = previousMasterKey;

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

test('authorization state survives store recreation in PostgreSQL server mode', { skip: !connectionString }, async () => {
  const pool = new pg.Pool({ connectionString });
  const ids = {
    user: 'pg-persist-user',
    organization: 'pg-persist-org',
    membership: 'pg-persist-membership'
  };
  try {
    await pool.query('delete from memberships where id = $1', [ids.membership]);
    await pool.query('delete from users where id = $1', [ids.user]);
    await pool.query('delete from organizations where id = $1', [ids.organization]);
    await pool.query(`insert into users (id, external_subject, email, password_hash, status)
      values ($1, $2, $3, $4, 'active')`, [ids.user, 'synthetic:pg-persist-user', 'pg-persist@example.test', '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi']);
    await pool.query(`insert into organizations (id, name, type, status)
      values ($1, 'Persistent Beta Test', 'clinic', 'active')`, [ids.organization]);
    await pool.query(`insert into memberships (id, user_id, organization_id, role, status, valid_until, scopes)
      values ($1, $2, $3, 'professional', 'active', '2099-01-01T00:00:00Z', $4)`, [ids.membership, ids.user, ids.organization, ['esdm_goal.read']]);

    const firstStore = createStore({ pool, persistAuthorization: true });
    await firstStore.hydrateAuthorization();
    const membership = firstStore.memberships.find((item) => item.id === ids.membership);
    assert.equal(membership.status, 'active');
    membership.status = 'revoked';
    await firstStore.flushAuthorizationState();

    const secondStore = createStore({ pool, persistAuthorization: true });
    await secondStore.hydrateAuthorization();
    assert.equal(secondStore.memberships.find((item) => item.id === ids.membership).status, 'revoked');
  } finally {
    await pool.query('delete from memberships where id = $1', [ids.membership]);
    await pool.query('delete from users where id = $1', [ids.user]);
    await pool.query('delete from organizations where id = $1', [ids.organization]);
    await pool.end();
  }
});
