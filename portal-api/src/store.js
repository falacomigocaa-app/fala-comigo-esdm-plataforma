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
  owner: ['organization.read', 'organization.key.read', 'membership.read', 'access.invite', 'access.read', 'access.revoke', 'benefit.read', 'audit.read', 'esdm_goal.read', 'esdm_goal.write', 'routine.read', 'school_collection.read', 'school_collection.write'],
  org_admin: ['organization.read', 'organization.key.read', 'membership.read', 'access.invite', 'access.read', 'benefit.read', 'esdm_goal.read', 'esdm_goal.write', 'routine.read', 'school_collection.read', 'school_collection.write'],
  professional: ['organization.read', 'access.read', 'esdm_goal.read', 'esdm_goal.write'],
  teacher: ['organization.read', 'access.read', 'routine.read', 'school_collection.read', 'school_collection.write'],
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
    refreshTokens: new Map(),
    organizationKeys: new Map(),
    auditEvents: [],
    idempotency: new Map(),
    pool,
    storageMode: pool ? 'postgres' : 'memory-test-only',

    async getOrganizationKey(organizationId) {
      let encryptedValue;
      if (pool) {
        const result = await pool.query(`
          select organization_id, key_encrypted
            from organization_keys
           where organization_id = $1
        `, [organizationId]);
        encryptedValue = result.rows[0]?.key_encrypted;
      } else {
        encryptedValue = store.organizationKeys.get(organizationId)?.keyEncrypted;
      }
      if (!encryptedValue) return null;
      return {
        organizationId,
        organizationKey: organizationKeyToBase64(decryptOrganizationKey(encryptedValue, { organizationId }))
      };
    },

    async provisionOrganizationKey({ organizationId, createdByUserId, now = new Date() }) {
      const keyEncrypted = encryptOrganizationKey(generateOrganizationKey(), { organizationId, now });
      if (pool) {
        await pool.query(`
          insert into organization_keys (organization_id, key_encrypted, key_version, created_by_user_id, rotated_by_user_id, created_at, rotated_at)
          values ($1, $2, 1, $3, $3, $4, $4)
          on conflict (organization_id) do update set
            key_encrypted = excluded.key_encrypted,
            key_version = organization_keys.key_version + 1,
            rotated_by_user_id = excluded.rotated_by_user_id,
            rotated_at = excluded.rotated_at
        `, [organizationId, keyEncrypted, createdByUserId, now.toISOString()]);
      } else {
        store.organizationKeys.set(organizationId, {
          keyEncrypted,
          keyVersion: (store.organizationKeys.get(organizationId)?.keyVersion ?? 0) + 1,
          createdByUserId,
          rotatedByUserId: createdByUserId,
          createdAt: now.toISOString(),
          rotatedAt: now.toISOString()
        });
      }
      return store.getOrganizationKey(organizationId);
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
