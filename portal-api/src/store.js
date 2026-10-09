import pg from 'pg';
import { randomUUID } from 'node:crypto';
import bcrypt from 'bcryptjs';
import {
  DEFAULT_REFRESH_TOKEN_EXPIRATION_MS,
  createOpaqueRefreshToken,
  hashRefreshToken
} from './services/auth.service.js';
import {
  decryptOrganizationKey,
  encryptOrganizationKey,
  generateOrganizationKey,
  organizationKeyToBase64
} from './services/organization-key.service.js';
import { AuthorizationError } from './authorization.js';
import { BillingError, hashBillingPayload } from './services/billing.service.js';

const { Pool } = pg;

export const esdmTranslations = {
  CE_N1_I5: {
    missaoPais: 'Estimular o uso da voz para pedir itens no dia a dia.',
    dicaPratica: 'Aproxime o item favorito do seu rosto, espere uma vocalização e entregue imediatamente após qualquer tentativa.'
  },
  CE_N1_I6: {
    missaoPais: 'Ajudar a criança a escolher entre duas opções.',
    dicaPratica: 'Apresente duas opções visíveis, aguarde a iniciativa e valide qualquer gesto, olhar ou vocalização de escolha.'
  },
  SOC_N1_I3: {
    missaoPais: 'Fortalecer a participação em uma troca social curta.',
    dicaPratica: 'Siga o interesse da criança, faça uma pausa previsível e responda de forma alegre quando ela iniciar a interação.'
  }
};

const baseUsers = [
  { id: 'user-admin-alpha', email: 'admin@fala-comigo.test', passwordHash: '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi', externalSubject: 'synthetic:admin-alpha', status: 'active' },
  { id: 'user-professional-alpha', email: 'profissional@fala-comigo.test', passwordHash: '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi', externalSubject: 'synthetic:professional-alpha', status: 'active' },
  { id: 'user-admin-beta', email: 'admin.beta@fala-comigo.test', passwordHash: '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi', externalSubject: 'synthetic:admin-beta', status: 'active' },
  { id: 'user-outsider', email: 'outsider@fala-comigo.test', passwordHash: '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi', externalSubject: 'synthetic:outsider', status: 'active' },
  { id: 'user-invitee-alpha', email: 'invitee@fala-comigo.test', passwordHash: '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi', externalSubject: 'synthetic:invitee-alpha', status: 'active' }
];

const baseOrganizations = [
  { id: 'org-demo-alpha', name: 'Clínica Aurora Demo', status: 'active', type: 'clinic' },
  { id: 'org-demo-beta', name: 'Escola Horizonte Demo', status: 'active', type: 'school' }
];

const roleScopes = {
  owner: ['organization.read', 'organization.key.read', 'organization.key.rotate', 'membership.read', 'access.invite', 'access.read', 'access.revoke', 'benefit.read', 'audit.read', 'esdm_goal.read', 'esdm_goal.write', 'routine.read', 'routine.write', 'school_collection.read', 'school_collection.write'],
  org_admin: ['organization.read', 'organization.key.read', 'membership.read', 'access.invite', 'access.read', 'benefit.read', 'esdm_goal.read', 'esdm_goal.write', 'routine.read', 'routine.write', 'school_collection.read', 'school_collection.write'],
  professional: ['organization.read', 'access.read', 'esdm_goal.read', 'esdm_goal.write'],
  teacher: ['organization.read', 'access.read', 'routine.read', 'routine.write', 'school_collection.read', 'school_collection.write'],
  caregiver: ['organization.read', 'access.read'],
  outsider: []
};

const DUMMY_PASSWORD_HASH = '$2b$12$u7hinMZXhMWNJXvBs90RauPnmv8zVvZcSh7ohICCg/S9TJAESRqSi';

const baseMemberships = [
  { id: 'membership-admin-alpha', userId: 'user-admin-alpha', organizationId: 'org-demo-alpha', role: 'owner', status: 'active', validUntil: '2099-01-01T00:00:00.000Z' },
  { id: 'membership-professional-alpha', userId: 'user-professional-alpha', organizationId: 'org-demo-alpha', role: 'professional', status: 'active', validUntil: '2099-01-01T00:00:00.000Z' },
  { id: 'membership-admin-beta', userId: 'user-admin-beta', organizationId: 'org-demo-beta', role: 'owner', status: 'active', validUntil: '2099-01-01T00:00:00.000Z' }
];

const baseSubjects = [
  { id: 'subject-demo-child', familySpaceId: 'family-demo-alpha', ownerUserId: 'user-admin-alpha', displayName: 'Criança Demo', status: 'active' }
];

const baseInvitations = [
  { id: 'invite-alpha-pending', organizationId: 'org-demo-alpha', inviteeUserId: 'user-invitee-alpha', role: 'professional', status: 'pending', expiresAt: '2099-01-01T00:00:00.000Z' },
  { id: 'invite-alpha-expired', organizationId: 'org-demo-alpha', inviteeUserId: 'user-invitee-alpha', role: 'professional', status: 'pending', expiresAt: '2020-01-01T00:00:00.000Z' }
];

const baseBenefits = [
  { id: 'benefit-demo-alpha', organizationId: 'org-demo-alpha', status: 'active', validUntil: '2099-01-01T00:00:00.000Z' }
];

const baseConsents = [
  { id: 'consent-demo-clinic', subjectId: 'subject-demo-child', organizationId: 'org-demo-alpha', grantedByUserId: 'user-admin-alpha', recipientUserId: 'user-professional-alpha', purpose: 'metas ESDM sintéticas', scopes: ['esdm_goal.read', 'esdm_goal.write'], noticeVersion: 'synthetic-v1', status: 'active', validUntil: '2099-01-01T00:00:00.000Z', createdAt: '2026-10-04T00:00:00.000Z', revokedAt: null },
  { id: 'consent-demo-school', subjectId: 'subject-demo-child', organizationId: 'org-demo-beta', grantedByUserId: 'user-admin-alpha', recipientUserId: 'user-admin-beta', purpose: 'rotina escolar sintética', scopes: ['routine.read', 'school_collection.read', 'school_collection.write'], noticeVersion: 'synthetic-v1', status: 'active', validUntil: '2099-01-01T00:00:00.000Z', createdAt: '2026-10-04T00:00:00.000Z', revokedAt: null }
];

const baseGrants = [
  { id: 'grant-demo-clinic', userId: 'user-professional-alpha', subjectId: 'subject-demo-child', organizationId: 'org-demo-alpha', consentId: 'consent-demo-clinic', purpose: 'metas ESDM sintéticas', scopes: ['esdm_goal.read', 'esdm_goal.write'], status: 'active', validUntil: '2099-01-01T00:00:00.000Z' },
  { id: 'grant-demo-school', userId: 'user-admin-beta', subjectId: 'subject-demo-child', organizationId: 'org-demo-beta', consentId: 'consent-demo-school', purpose: 'rotina escolar sintética', scopes: ['routine.read', 'school_collection.read', 'school_collection.write'], status: 'active', validUntil: '2099-01-01T00:00:00.000Z' }
];

function mapGoal(row) {
  return {
    id: row.id,
    subjectId: row.subject_id,
    codigoTecnicoDenver: row.codigo_tecnico_denver,
    missaoPais: row.missao_pais,
    dicaPratica: row.dica_pratica,
    status: row.status,
    passoAtualAba: row.passo_atual_aba,
    createdByUserId: row.created_by_user_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapCollection(row) {
  return {
    id: row.id,
    subjectId: row.subject_id,
    organizationId: row.organization_id,
    encryptedData: row.encrypted_data,
    iv: row.iv,
    dataRegistro: row.data_registro,
    blocoRotinaEscolar: row.bloco_rotina_escolar,
    nivelSuporte: row.nivel_suporte,
    createdByUserId: row.created_by_user_id,
    createdAt: row.created_at
  };
}

function mapTransitionAlert(row) {
  const payload = row.payload && typeof row.payload === 'object' ? row.payload : {};
  return {
    ...payload,
    id: row.alert_id,
    subjectId: row.subject_id,
    organizationId: row.organization_id,
    remoteUpdatedAt: row.updated_at,
    remoteVersion: row.updated_at ? new Date(row.updated_at).getTime() : null
  };
}

function mapLocationUpdate(row) { return { id: row.id, subjectId: row.subject_id ?? row.subjectId, organizationId: row.organization_id ?? row.organizationId, encryptedData: row.encrypted_data ?? row.encryptedData, iv: row.iv, clientRecordedAt: row.client_recorded_at ?? row.clientRecordedAt, createdAt: row.created_at ?? row.createdAt }; }

function createPostgresPool() {
  if (!process.env.DATABASE_URL) return null;

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    max: Number(process.env.PGPOOL_MAX ?? 10),
    idleTimeoutMillis: Number(process.env.PGPOOL_IDLE_TIMEOUT_MS ?? 30_000),
    connectionTimeoutMillis: Number(process.env.PGPOOL_CONNECTION_TIMEOUT_MS ?? 5_000),
    ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : undefined
  });

  pool.on('error', (error) => {
    console.error('[portal-api] erro inesperado no Pool PostgreSQL:', error.message);
  });
  return pool;
}

export function createStore({ pool = createPostgresPool() } = {}) {
  const store = {
    users: structuredClone(baseUsers),
    organizations: structuredClone(baseOrganizations),
    memberships: structuredClone(baseMemberships),
    subjects: structuredClone(baseSubjects),
    relationships: [],
    consents: structuredClone(baseConsents),
    invitations: structuredClone(baseInvitations),
    grants: structuredClone(baseGrants),
    benefits: structuredClone(baseBenefits),
    goals: [],
    collections: [],
    transitionAlerts: [],
    locationUpdates: [],
    refreshTokens: new Map(),
    organizationKeys: new Map(),
    organizationKeyVersions: new Map(),
    subscriptions: new Map(),
    checkouts: new Map(),
    billingEvents: new Map(),
    auditEvents: [],
    idempotency: new Map(),
    pool,
    storageMode: pool ? 'postgres' : 'memory-test-only',

    async getOrganizationKey(organizationId, requestedVersion = null) {
      let encryptedValue;
      let keyVersion;
      if (pool) {
        const result = requestedVersion == null
          ? await pool.query('select organization_id, key_encrypted, key_version from organization_keys where organization_id = $1', [organizationId])
          : await pool.query('select organization_id, key_encrypted, key_version from organization_key_versions where organization_id = $1 and key_version = $2 and retired_at is null', [organizationId, requestedVersion]);
        encryptedValue = result.rows[0]?.key_encrypted;
        keyVersion = result.rows[0]?.key_version;
      } else if (requestedVersion == null) {
        const current = store.organizationKeys.get(organizationId);
        encryptedValue = current?.keyEncrypted;
        keyVersion = current?.keyVersion;
      } else {
        const version = store.organizationKeyVersions.get(organizationId)?.get(requestedVersion);
        encryptedValue = version?.keyEncrypted;
        keyVersion = version?.keyVersion;
      }
      if (!encryptedValue) return null;
      return { organizationId, keyVersion, organizationKey: organizationKeyToBase64(decryptOrganizationKey(encryptedValue, { organizationId })) };
    },

    async provisionOrganizationKey({ organizationId, createdByUserId, now = new Date() }) {
      let nextVersion = 1;
      if (pool) {
        const current = await pool.query('select key_version from organization_keys where organization_id = $1', [organizationId]);
        nextVersion = (current.rows[0]?.key_version ?? 0) + 1;
      } else nextVersion = (store.organizationKeys.get(organizationId)?.keyVersion ?? 0) + 1;
      const keyEncrypted = encryptOrganizationKey(generateOrganizationKey(), { organizationId, now });
      if (pool) {
        const client = await pool.connect();
        try {
          await client.query('begin');
          await client.query(`insert into organization_keys (organization_id, key_encrypted, key_version, created_by_user_id, rotated_by_user_id, created_at, rotated_at) values ($1,$2,$3,$4,$4,$5,$5) on conflict (organization_id) do update set key_encrypted=excluded.key_encrypted, key_version=excluded.key_version, rotated_by_user_id=excluded.rotated_by_user_id, rotated_at=excluded.rotated_at`, [organizationId, keyEncrypted, nextVersion, createdByUserId, now.toISOString()]);
          await client.query(`insert into organization_key_versions (organization_id, key_version, key_encrypted, created_by_user_id, created_at) values ($1,$2,$3,$4,$5)`, [organizationId, nextVersion, keyEncrypted, createdByUserId, now.toISOString()]);
          await client.query('commit');
        } catch (error) { await client.query('rollback'); throw error; } finally { client.release(); }
      } else {
        store.organizationKeys.set(organizationId, { keyEncrypted, keyVersion: nextVersion, createdByUserId, rotatedByUserId: createdByUserId, createdAt: now.toISOString(), rotatedAt: now.toISOString() });
        const versions = store.organizationKeyVersions.get(organizationId) ?? new Map();
        versions.set(nextVersion, { keyEncrypted, keyVersion: nextVersion });
        store.organizationKeyVersions.set(organizationId, versions);
      }
      return store.getOrganizationKey(organizationId);
    },

    async getSubscription(organizationId) {
      if (pool) {
        const result = await pool.query(`select id, organization_id as "organizationId", plan_id as "planId", status, provider, provider_subscription_id as "providerSubscriptionId", current_period_start as "currentPeriodStart", current_period_end as "currentPeriodEnd", cancel_at_period_end as "cancelAtPeriodEnd", created_at as "createdAt" from subscriptions where organization_id = $1 order by updated_at desc limit 1`, [organizationId]);
        return result.rows[0] ?? null;
      }
      return store.subscriptions.get(organizationId) ?? null;
    },

    async createPendingSubscription(checkout, now = new Date()) {
      const existing = await store.getSubscription(checkout.organizationId);
      if (existing && ['pending_payment', 'active', 'grace'].includes(existing.status)) throw new BillingError('SUBSCRIPTION_ALREADY_ACTIVE', 409);
      const subscription = { id: `sub_${checkout.id.slice('checkout_'.length)}`, organizationId: checkout.organizationId, planId: checkout.planId, status: 'pending_payment', provider: 'sandbox', providerSubscriptionId: null, currentPeriodStart: null, currentPeriodEnd: null, cancelAtPeriodEnd: false, createdByUserId: checkout.userId, createdAt: now.toISOString(), updatedAt: now.toISOString() };
      if (pool) await pool.query(`insert into subscriptions (id, organization_id, plan_id, status, provider, created_by_user_id, created_at, updated_at) values ($1,$2,$3,$4,$5,$6,$7,$7)`, [subscription.id, subscription.organizationId, subscription.planId, subscription.status, subscription.provider, subscription.createdByUserId, now.toISOString()]);
      else store.subscriptions.set(subscription.organizationId, subscription);
      store.checkouts.set(checkout.id, checkout);
      return subscription;
    },

    async processBillingEvent(event, now = new Date()) {
      const payloadHash = hashBillingPayload(event);
      if (pool) {
        const existing = await pool.query('select id, status from billing_events where id = $1', [event.id]);
        if (existing.rows[0]) return { duplicate: true, status: existing.rows[0].status };
        await pool.query("insert into billing_events (id, provider, event_type, payload_hash, status) values ($1,'sandbox',$2,$3,'received')", [event.id, event.type, payloadHash]);
      } else if (store.billingEvents.has(event.id)) return { duplicate: true, status: store.billingEvents.get(event.id).status };
      else store.billingEvents.set(event.id, { id: event.id, status: 'received', payloadHash });
      const organizationId = event.data?.organizationId;
      const subscription = organizationId ? await store.getSubscription(organizationId) : null;
      if (!subscription) return { duplicate: false, status: 'ignored' };
      const nextStatus = event.type === 'checkout.completed' || event.type === 'subscription.activated' ? 'active' : event.type === 'subscription.canceled' ? 'canceled' : null;
      if (!nextStatus) return { duplicate: false, status: 'ignored' };
      const periodEnd = event.data?.currentPeriodEnd ?? new Date(now.getTime() + 30 * 86400000).toISOString();
      if (pool) {
        await pool.query(`update subscriptions set status=$2, provider_subscription_id=coalesce($3, provider_subscription_id), current_period_start=$4, current_period_end=$5, updated_at=$6 where organization_id=$1`, [organizationId, nextStatus, event.data?.providerSubscriptionId ?? null, now.toISOString(), periodEnd, now.toISOString()]);
        await pool.query("update billing_events set status='processed', processed_at=$2 where id=$1", [event.id, now.toISOString()]);
      } else { Object.assign(subscription, { status: nextStatus, providerSubscriptionId: event.data?.providerSubscriptionId ?? subscription.providerSubscriptionId, currentPeriodStart: now.toISOString(), currentPeriodEnd: periodEnd, updatedAt: now.toISOString() }); store.billingEvents.get(event.id).status = 'processed'; }
      return { duplicate: false, status: 'processed', subscription: await store.getSubscription(organizationId) };
    },

    async saveLocationUpdate({ id, subjectId, organizationId, encryptedData, iv, clientRecordedAt, createdByUserId }) {
      if (pool) {
        const result = await pool.query(`insert into location_updates (id, subject_id, organization_id, encrypted_data, iv, client_recorded_at, created_by_user_id) values ($1,$2,$3,$4,$5,$6,$7) on conflict (id) do update set encrypted_data=excluded.encrypted_data, iv=excluded.iv returning *`, [id, subjectId, organizationId, encryptedData, iv, clientRecordedAt, createdByUserId]);
        return mapLocationUpdate(result.rows[0]);
      }
      const record = { id, subjectId, organizationId, encryptedData, iv, clientRecordedAt, createdByUserId, createdAt: new Date().toISOString() };
      const index = store.locationUpdates.findIndex((item) => item.id === id);
      if (index >= 0) store.locationUpdates[index] = record; else store.locationUpdates.push(record);
      return record;
    },
    async getLatestLocationUpdate(subjectId, organizationId) {
      if (pool) { const result = await pool.query('select * from location_updates where subject_id=$1 and organization_id=$2 order by client_recorded_at desc limit 1', [subjectId, organizationId]); return result.rows[0] ? mapLocationUpdate(result.rows[0]) : null; }
      const latest = store.locationUpdates.filter((item) => item.subjectId === subjectId && item.organizationId === organizationId).sort((a,b) => new Date(b.clientRecordedAt) - new Date(a.clientRecordedAt))[0];
      return latest ?? null;
    },
    async revokeLocationUpdates(subjectId, organizationId) {
      if (pool) { await pool.query('delete from location_updates where subject_id=$1 and organization_id=$2', [subjectId, organizationId]); return; }
      store.locationUpdates = store.locationUpdates.filter((item) => !(item.subjectId === subjectId && item.organizationId === organizationId));
    },

    async revokeConsent({ subjectId, consentId, now = new Date() }) {
      if (pool) {
        const result = await pool.query("update consents set status='revoked', revoked_at=$3 where id=$1 and subject_id=$2 and status='active' returning id, subject_id as \"subjectId\", organization_id as \"organizationId\", status, revoked_at as \"revokedAt\"", [consentId, subjectId, now.toISOString()]);
        await pool.query("update access_grants set status='revoked' where consent_id=$1", [consentId]);
        return result.rows[0] ?? null;
      }
      const consent = store.consents.find((item) => item.id === consentId && item.subjectId === subjectId);
      if (!consent) return null;
      consent.status = 'revoked';
      consent.revokedAt = now.toISOString();
      for (const grant of store.grants.filter((item) => item.consentId === consentId)) grant.status = 'revoked';
      return consent;
    },
    async deleteSubjectData(subjectId) {
      if (pool) {
        for (const table of ['location_updates', 'transition_alerts', 'school_collections', 'esdm_goals']) await pool.query(`delete from ${table} where subject_id=$1`, [subjectId]);
        await pool.query("update access_grants set status='revoked' where subject_id=$1", [subjectId]);
        await pool.query("update consents set status='revoked', revoked_at=now() where subject_id=$1 and status='active'", [subjectId]);
        return;
      }
      store.locationUpdates = store.locationUpdates.filter((item) => item.subjectId !== subjectId);
      store.transitionAlerts = store.transitionAlerts.filter((item) => item.subjectId !== subjectId);
      store.collections = store.collections.filter((item) => item.subjectId !== subjectId);
      store.goals = store.goals.filter((item) => item.subjectId !== subjectId);
      for (const grant of store.grants.filter((item) => item.subjectId === subjectId)) grant.status = 'revoked';
      for (const consent of store.consents.filter((item) => item.subjectId === subjectId && item.status === 'active')) { consent.status = 'revoked'; consent.revokedAt = new Date().toISOString(); }
    },
    async getSubjectDataSummary(subjectId) {
      if (pool) {
        const result = await pool.query(`select (select count(*) from esdm_goals where subject_id=$1) as goals, (select count(*) from school_collections where subject_id=$1) as collections, (select count(*) from transition_alerts where subject_id=$1) as transition_alerts, (select count(*) from location_updates where subject_id=$1) as location_updates, (select count(*) from consents where subject_id=$1) as consents`, [subjectId]);
        return Object.fromEntries(Object.entries(result.rows[0]).map(([key, value]) => [key, Number(value)]));
      }
      return { goals: store.goals.filter((item) => item.subjectId === subjectId).length, collections: store.collections.filter((item) => item.subjectId === subjectId).length, transition_alerts: store.transitionAlerts.filter((item) => item.subjectId === subjectId).length, location_updates: store.locationUpdates.filter((item) => item.subjectId === subjectId).length, consents: store.consents.filter((item) => item.subjectId === subjectId).length };
    },
    async saveGoal({ subjectId, codigoTecnicoDenver, status = 'Em Progresso', passoAtualAba = 1, createdByUserId }) {
      const translation = esdmTranslations[codigoTecnicoDenver];
      if (!translation) throw new Error('INVALID_ESDM_CODE');
      const id = `goal-${randomUUID()}`;
      if (pool) {
        const result = await pool.query(`
          insert into esdm_goals (id, subject_id, codigo_tecnico_denver, missao_pais, dica_pratica, status, passo_atual_aba, created_by_user_id)
          values ($1,$2,$3,$4,$5,$6,$7,$8) returning *
        `, [id, subjectId, codigoTecnicoDenver, translation.missaoPais, translation.dicaPratica, status, passoAtualAba, createdByUserId]);
        return mapGoal(result.rows[0]);
      }
      const goal = { id, subjectId, codigoTecnicoDenver, ...translation, status, passoAtualAba, createdByUserId, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
      store.goals.push(goal);
      return goal;
    },

    async getGoalsBySubject(subjectId) {
      if (pool) {
        const result = await pool.query('select * from esdm_goals where subject_id = $1 and status <> $2 order by created_at desc', [subjectId, 'Archived']);
        return result.rows.map(mapGoal);
      }
      return store.goals.filter((goal) => goal.subjectId === subjectId && goal.status !== 'Archived');
    },

    async saveCollection({ subjectId, organizationId, encryptedData, iv, dataRegistro, createdByUserId }) {
      const id = `collection-${randomUUID()}`;
      if (pool) {
        const result = await pool.query(`
          insert into school_collections (id, subject_id, organization_id, encrypted_data, iv, data_registro, created_by_user_id)
          values ($1,$2,$3,$4,$5,$6,$7) returning *
        `, [id, subjectId, organizationId, encryptedData, iv, dataRegistro, createdByUserId]);
        return mapCollection(result.rows[0]);
      }
      const collection = {
        id,
        subjectId,
        organizationId,
        encryptedData,
        iv,
        dataRegistro,
        blocoRotinaEscolar: null,
        nivelSuporte: null,
        createdByUserId,
        createdAt: new Date().toISOString()
      };
      store.collections.push(collection);
      return collection;
    },

    async getCollectionsBySubject(subjectId) {
      if (pool) {
        const result = await pool.query('select * from school_collections where subject_id = $1 order by data_registro desc', [subjectId]);
        return result.rows.map(mapCollection);
      }
      return store.collections.filter((collection) => collection.subjectId === subjectId).sort((a, b) => new Date(b.dataRegistro) - new Date(a.dataRegistro));
    },

    async upsertTransitionAlert({ alertId, subjectId, organizationId, payload, clientUpdatedAt, createdByUserId }) {
      const clientDate = new Date(clientUpdatedAt);
      if (Number.isNaN(clientDate.getTime())) throw new AuthorizationError('INVALID_ALERT', 400);
      if (pool) {
        const result = await pool.query(`
          insert into transition_alerts
            (alert_id, subject_id, organization_id, payload, client_updated_at, created_by_user_id)
          values ($1,$2,$3,$4::jsonb,$5,$6)
          on conflict (subject_id, alert_id) do update set
            organization_id = excluded.organization_id,
            payload = excluded.payload,
            client_updated_at = excluded.client_updated_at,
            updated_at = now()
          where transition_alerts.client_updated_at <= excluded.client_updated_at
          returning *
        `, [alertId, subjectId, organizationId, JSON.stringify(payload), clientDate.toISOString(), createdByUserId]);
        if (result.rows[0]) return mapTransitionAlert(result.rows[0]);
        throw new AuthorizationError('VERSION_CONFLICT', 409);
      }

      const existing = store.transitionAlerts.find(
        (item) => item.alertId === alertId && item.subjectId === subjectId,
      );
      if (existing && new Date(existing.clientUpdatedAt) > clientDate) {
        throw new AuthorizationError('VERSION_CONFLICT', 409);
      }
      const record = {
        alertId,
        subjectId,
        organizationId,
        payload: structuredClone(payload),
        clientUpdatedAt: clientDate.toISOString(),
        createdByUserId,
        createdAt: existing?.createdAt ?? new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };
      if (existing) Object.assign(existing, record);
      else store.transitionAlerts.push(record);
      return mapTransitionAlert({
        ...record,
        alert_id: alertId,
        subject_id: subjectId,
        organization_id: organizationId,
        updated_at: record.updatedAt
      });
    },

    async getTransitionAlertsBySubject(subjectId, organizationId) {
      if (pool) {
        const result = await pool.query(`
          select * from transition_alerts
           where subject_id = $1 and organization_id = $2
           order by client_updated_at desc
        `, [subjectId, organizationId]);
        return result.rows.map(mapTransitionAlert);
      }
      return store.transitionAlerts
        .filter((item) => item.subjectId === subjectId && item.organizationId === organizationId)
        .sort((left, right) => new Date(right.clientUpdatedAt) - new Date(left.clientUpdatedAt))
        .map((item) => mapTransitionAlert({
          ...item,
          alert_id: item.alertId,
          subject_id: item.subjectId,
          organization_id: item.organizationId,
          updated_at: item.updatedAt
        }));
    },

    async deleteTransitionAlert({ alertId, subjectId, organizationId }) {
      if (pool) {
        await pool.query(
          'delete from transition_alerts where alert_id = $1 and subject_id = $2 and organization_id = $3',
          [alertId, subjectId, organizationId],
        );
        return;
      }
      store.transitionAlerts = store.transitionAlerts.filter(
        (item) => !(item.alertId === alertId && item.subjectId === subjectId && item.organizationId === organizationId),
      );
    },

    async authenticateCredentials({ email, password }, now = new Date()) {
      const normalizedEmail = typeof email === 'string' ? email.trim().toLowerCase() : '';
      const suppliedPassword = typeof password === 'string' ? password : '';
      let user;
      let membership;

      if (pool) {
        const result = await pool.query(`
          select u.id, u.email, u.password_hash, m.organization_id, m.role
            from users u
            join memberships m on m.user_id = u.id
           where lower(u.email) = $1
             and u.status = 'active'
             and m.status = 'active'
             and m.valid_until > $2
           order by m.valid_until desc
           limit 1
        `, [normalizedEmail, now.toISOString()]);
        const row = result.rows[0];
        if (row) {
          user = row;
          membership = row;
        }
      } else {
        user = store.users.find((candidate) => candidate.email === normalizedEmail && candidate.status === 'active');
        membership = user
          ? store.memberships
              .filter((candidate) => candidate.userId === user.id && candidate.status === 'active' && new Date(candidate.validUntil) > now)
              .sort((left, right) => new Date(right.validUntil) - new Date(left.validUntil))[0]
          : null;
      }

      const passwordHash = user?.passwordHash ?? user?.password_hash ?? DUMMY_PASSWORD_HASH;
      const passwordMatches = await bcrypt.compare(suppliedPassword, passwordHash);
      if (!user || !membership || !passwordMatches) {
        throw new AuthorizationError('INVALID_CREDENTIALS', 401);
      }

      const role = membership.role;
      return {
        userId: user.id,
        organizationId: membership.organizationId ?? membership.organization_id,
        scopes: roleScopes[role] ?? []
      };
    },

    async createRefreshToken({ userId, organizationId, scopes }, now = new Date()) {
      const token = createOpaqueRefreshToken();
      const tokenHash = hashRefreshToken(token);
      const expiresAt = new Date(now.getTime() + DEFAULT_REFRESH_TOKEN_EXPIRATION_MS).toISOString();
      if (pool) {
        await pool.query(`
          insert into refresh_tokens (token_hash, user_id, organization_id, scopes, expires_at)
          values ($1, $2, $3, $4::jsonb, $5)
        `, [tokenHash, userId, organizationId, JSON.stringify([...new Set(scopes)]), expiresAt]);
        return token;
      }
      store.refreshTokens.set(tokenHash, {
        userId,
        organizationId,
        scopes: [...new Set(scopes)],
        createdAt: now.toISOString(),
        expiresAt,
        revokedAt: null
      });
      return token;
    },

    async rotateRefreshToken(token, now = new Date()) {
      let tokenHash;
      try {
        tokenHash = hashRefreshToken(token);
      } catch (_) {
        throw new AuthorizationError('REFRESH_TOKEN_INVALID', 401);
      }
      if (pool) {
        const result = await pool.query(`
          update refresh_tokens
             set revoked_at = $2
           where token_hash = $1
             and revoked_at is null
             and expires_at > $2
           returning user_id, organization_id, scopes
        `, [tokenHash, now.toISOString()]);
        const record = result.rows[0];
        if (!record) throw new AuthorizationError('REFRESH_TOKEN_INVALID', 401);
        return {
          userId: record.user_id,
          organizationId: record.organization_id,
          scopes: Array.isArray(record.scopes) ? record.scopes : JSON.parse(record.scopes)
        };
      }
      const record = store.refreshTokens.get(tokenHash);
      if (!record || record.revokedAt || new Date(record.expiresAt) <= now) {
        throw new AuthorizationError('REFRESH_TOKEN_INVALID', 401);
      }
      record.revokedAt = now.toISOString();
      return {
        userId: record.userId,
        organizationId: record.organizationId,
        scopes: [...record.scopes]
      };
    }
  };

  // Aliases de domínio preservados para compatibilidade com consumidores existentes.
  store.createGoal = store.saveGoal;
  store.listGoals = store.getGoalsBySubject;
  store.createCollection = store.saveCollection;
  store.listCollections = store.getCollectionsBySubject;
  return store;
}

export { roleScopes };
