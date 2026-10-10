import { handleOnboarding } from './onboarding.js';
import { randomUUID } from 'node:crypto';
import { AuthorizationError, audit, requireScope, membershipFor, stableError } from './authorization.js';
import { authenticateRequest } from './middlewares/auth.middleware.js';
import { issueAccessToken } from './services/auth.service.js';
import { createStore, esdmTranslations, effectiveScopes } from './store.js';

const jsonHeaders = { 'content-type': 'application/json; charset=utf-8' };

function response(status, body) {
  return { status, body };
}

function parsePath(url) {
  return new URL(url, 'http://localhost').pathname.split('/').filter(Boolean);
}

async function sendAudit(store, context, action, result, error = null) {
  await audit(store, {
    userId: context.user?.id ?? null,
    organizationId: context.organizationId,
    action,
    result,
    code: error?.code ?? null,
    requestId: context.requestId,
    now: context.now
  });
}

async function subjectForOwner(store, subjectId, userId) {
  const subject = await store.findRecord('subjects', { id: subjectId, status: 'active' });
  if (!subject || subject.ownerUserId !== userId) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
  return subject;
}

async function subjectById(store, subjectId) {
  const subject = await store.findRecord('subjects', { id: subjectId, status: 'active' });
  if (!subject) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
  return subject;
}

async function activeConsent(store, consentId, now) {
  const consent = await store.findRecord('consents', { id: consentId });
  if (!consent) throw new AuthorizationError('CONSENT_REQUIRED');
  if (consent.status === 'revoked') throw new AuthorizationError('REVOKED');
  if (consent.status !== 'active' || !(new Date(consent.validUntil) > now)) throw new AuthorizationError('EXPIRED');
  return consent;
}

async function grantFor(store, userId, subjectId, scope, now, organizationId) {
  const grant = (await store.listRecords('grants', { userId, subjectId, status: 'active', ...(organizationId ? { organizationId } : {}) })).find((item) => item.scopes.includes(scope));
  if (!grant) throw new AuthorizationError('GRANT_REQUIRED');
  if (!(new Date(grant.validUntil) > now)) throw new AuthorizationError('EXPIRED');
  const consent = await activeConsent(store, grant.consentId, now);
  await membershipFor(store, userId, grant.organizationId, now);
  const organization = await store.findRecord('organizations', { id: grant.organizationId, status: 'active' });
  if (!organization || consent.subjectId !== subjectId || consent.recipientUserId !== userId || consent.organizationId !== grant.organizationId || consent.purpose !== grant.purpose || !consent.scopes.includes(scope)) throw new AuthorizationError('CONSENT_MISMATCH');
  return { grant, consent };
}

async function subjectWithScope(store, subjectId, userId, scope, now, organizationId) {
  const subject = await subjectById(store, subjectId);
  if (subject.ownerUserId === userId) return { subject, grant: null };
  const { grant } = await grantFor(store, userId, subjectId, scope, now, organizationId);
  return { subject, grant };
}

function requireGoalCode(code) {
  if (!code || !esdmTranslations[code]) throw new AuthorizationError('INVALID_ESDM_CODE', 400);
  return esdmTranslations[code];
}

function isBase64(value) {
  return typeof value === 'string' && value.length > 0 && /^[A-Za-z0-9+/_-]+={0,2}$/.test(value);
}

function decodedByteLength(value) {
  try {
    return Buffer.from(value.replace(/-/g, '+').replace(/_/g, '/'), 'base64').length;
  } catch (_) {
    return 0;
  }
}

function requireEncryptedCollectionEnvelope(body, organizationId) {
  if (body?.organizationId !== organizationId) {
    throw new AuthorizationError('ORGANIZATION_MISMATCH');
  }
  if (!isBase64(body?.encryptedData) || decodedByteLength(body.encryptedData) <= 16 ||
      !isBase64(body?.iv) || decodedByteLength(body.iv) !== 12) {
    throw new AuthorizationError('INVALID_E2EE_ENVELOPE', 400);
  }
  return {
    organizationId,
    encryptedData: body.encryptedData,
    iv: body.iv
  };
}

export function createApp({ store = createStore(), now = () => new Date() } = {}) {
  async function handleRequest({ method, url, headers = {}, body = null }) {
    const path = parsePath(url);
    const requestId = headers['x-request-id'] ?? null;
    const clock = now();
    const context = { user: null, organizationId: null, requestId, now: clock };

    try {
      const onboarding = await handleOnboarding({ store, method, path, headers, body, context });
      if (onboarding) return onboarding;
      if (method === 'POST' && path[0] === 'v1' && path[1] === 'auth' && path[2] === 'login') {
        const claims = await store.authenticateCredentials(body ?? {}, clock);
        await membershipFor(store, claims.userId, claims.organizationId, clock);
        const accessToken = issueAccessToken(claims);
        const refreshToken = await store.createRefreshToken(claims, clock);
        const mayReadKey = claims.scopes.includes('organization.key.read');
        const organizationKey = process.env.MASTER_CRYPTO_KEY && mayReadKey
          ? await store.getOrganizationKey(claims.organizationId)
          : null;
        if (process.env.MASTER_CRYPTO_KEY && mayReadKey && !organizationKey) {
          throw new AuthorizationError('ORGANIZATION_KEY_UNAVAILABLE', 503);
        }
        return response(200, {
          userId: claims.userId,
          organizationId: claims.organizationId,
          scopes: claims.scopes,
          accessToken,
          refreshToken,
          expiresIn: 15 * 60,
          refreshExpiresIn: 7 * 24 * 60 * 60,
          ...(organizationKey ?? {})
        });
      }

      if (method === 'POST' && path[0] === 'v1' && path[1] === 'auth' && path[2] === 'refresh') {
        const claims = await store.rotateRefreshToken(body?.refreshToken, clock);
        const user = await store.findRecord('users', { id: claims.userId, status: 'active' });
        if (!user) throw new AuthorizationError('REFRESH_TOKEN_INVALID', 401);
        const membership = await membershipFor(store, claims.userId, claims.organizationId, clock);
        claims.scopes = (effectiveScopes(membership)).filter((scope) => claims.scopes.includes(scope));
        const accessToken = issueAccessToken(claims);
        const refreshToken = await store.createRefreshToken(claims, clock);
        return response(200, {
          accessToken,
          refreshToken,
          expiresIn: 15 * 60,
          refreshExpiresIn: 7 * 24 * 60 * 60
        });
      }

      if (method === 'GET' && path[0] === 'v1' && path[1] === 'me') {
        context.user = await authenticateRequest(store, headers);
        return response(200, { id: context.user.id, status: context.user.status, storageMode: store.storageMode });
      }

      context.user = await authenticateRequest(store, headers);
      context.organizationId = context.user.organizationId;
      if (path[0] !== 'v1') return response(404, { error: 'NOT_FOUND' });

      if (method === 'GET' && path[1] === 'organizations' && path[3] === 'keys') {
        context.organizationId = path[2];
        await requireScope(store, context.user.id, context.organizationId, 'organization.key.read', clock, context.user);
        const organizationKey = await store.getOrganizationKey(context.organizationId);
        if (!organizationKey) throw new AuthorizationError('ORGANIZATION_KEY_UNAVAILABLE', 404);
        await sendAudit(store, context, 'organization.key.read', 'allowed');
        return response(200, organizationKey);
      }

      if (method === 'GET' && path[1] === 'organizations' && path[3] === undefined && path[2]) {
        context.organizationId = path[2];
        await requireScope(store, context.user.id, context.organizationId, 'organization.read', clock, context.user);
        const organization = await store.findRecord('organizations', { id: context.organizationId, status: 'active' });
        if (!organization) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        await sendAudit(store, context, 'organization.read', 'allowed');
        return response(200, organization);
      }

      if (method === 'GET' && path[1] === 'organizations' && path[3] === 'memberships') {
        context.organizationId = path[2];
        await requireScope(store, context.user.id, context.organizationId, 'membership.read', clock, context.user);
        const memberships = await store.listRecords('memberships', { organizationId: context.organizationId });
        await sendAudit(store, context, 'membership.read', 'allowed');
        return response(200, { memberships: await Promise.all(memberships.map(async (member) => ({ ...member, email: (await store.findRecord('users', { id: member.userId }))?.email, scopes: effectiveScopes(member) }))) });
      }

      if (method === 'GET' && path[1] === 'organizations' && path[3] === 'subjects') {
        context.organizationId = path[2];
        await requireScope(store, context.user.id, context.organizationId, 'access.read', clock, context.user);
        const candidates = await store.listRecords('subjects', { status: 'active' });
        const subjects = [];
        for (const subject of candidates) {
          let allowed = subject.ownerUserId === context.user.id;
          if (!allowed) {
            const grants = await store.listRecords('grants', { userId: context.user.id, subjectId: subject.id, organizationId: context.organizationId, status: 'active' });
            for (const grant of grants) {
              if (!(new Date(grant.validUntil) > clock)) continue;
              try { const consent = await activeConsent(store, grant.consentId, clock); if (consent.subjectId === subject.id && consent.recipientUserId === context.user.id && consent.organizationId === context.organizationId && grant.scopes.some((scope) => consent.scopes.includes(scope))) allowed = true; } catch (_) { /* expired/revoked consent */ }
            }
          }
          if (allowed) subjects.push({ id: subject.id, displayName: subject.displayName, status: subject.status, isOwner: subject.ownerUserId === context.user.id, organizationId: context.organizationId });
        }
        await sendAudit(store, context, 'subject.list', 'allowed');
        return response(200, { subjects });
      }

      if (method === 'POST' && path[1] === 'subjects' && path[2] && path[3] === 'consents') {
        const subject = await subjectForOwner(store, path[2], context.user.id);
        const organizationId = body?.organizationId;
        const organization = await store.findRecord('organizations', { id: organizationId, status: 'active' });
        if (!organization) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        const scopes = Array.isArray(body?.scopes) ? [...new Set(body.scopes)] : [];
        if (scopes.length === 0 || !body?.purpose || !body?.recipientUserId) throw new AuthorizationError('INVALID_CONSENT', 400);
        const validUntil = body.validUntil ?? '2099-01-01T00:00:00.000Z';
        if (!(new Date(validUntil) > clock)) throw new AuthorizationError('EXPIRED');
        const consent = {
          id: `consent-${randomUUID()}`,
          subjectId: subject.id,
          organizationId,
          grantedByUserId: context.user.id,
          recipientUserId: body.recipientUserId,
          purpose: body.purpose,
          scopes,
          noticeVersion: body.noticeVersion ?? 'synthetic-v1',
          status: 'active',
          validUntil,
          createdAt: clock.toISOString(),
          revokedAt: null
        };
        await store.saveRecord('consents', consent);
        await sendAudit(store, context, 'consent.create', 'allowed');
        return response(201, consent);
      }

      if (path[1] === 'subjects' && path[2] && (path[3] === 'esdm-goals' || path[3] === 'school-collections')) {
        const subjectId = path[2];
        const resource = path[3];
        const isGoal = resource === 'esdm-goals';
        const readScope = isGoal ? 'esdm_goal.read' : 'school_collection.read';
        const writeScope = isGoal ? 'esdm_goal.write' : 'school_collection.write';
        const requiredScope = method === 'POST' ? writeScope : readScope;
        await requireScope(store, context.user.id, context.user.organizationId, requiredScope, clock, context.user);
        if (!context.user.scopes.includes(requiredScope)) throw new AuthorizationError('SCOPE_DENIED');
        const { subject, grant } = await subjectWithScope(store, subjectId, context.user.id, requiredScope, clock, context.user.organizationId);
        if (grant && grant.organizationId !== context.user.organizationId) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        context.organizationId = grant?.organizationId ?? context.user.organizationId;

        if (method === 'GET' && isGoal) {
          const goals = await store.getGoalsBySubject(subject.id);
          await sendAudit(store, context, 'esdm_goal.read', 'allowed');
          return response(200, { goals });
        }
        if (method === 'POST' && isGoal) {
          const translation = requireGoalCode(body?.codigoTecnicoDenver);
          const result = await store.idempotent({ requestId, userId: context.user.id, organizationId: context.organizationId, method, url }, body, () => store.saveGoal({
            subjectId: subject.id,
            codigoTecnicoDenver: body.codigoTecnicoDenver,
            status: body.status ?? 'Em Progresso',
            passoAtualAba: Number.isInteger(body.passoAtualAba) ? body.passoAtualAba : 1,
            createdByUserId: context.user.id
          }));
          await sendAudit(store, context, 'esdm_goal.create', 'allowed');
          return response(201, { goal: { ...result, ...translation } });
        }
        if (method === 'GET' && !isGoal) {
          const collections = await store.getCollectionsBySubject(subject.id, context.organizationId);
          await sendAudit(store, context, 'school_collection.read', 'allowed');
          return response(200, { collections });
        }
        if (method === 'POST' && !isGoal) {
          const envelope = requireEncryptedCollectionEnvelope(body, context.user.organizationId);
          const result = await store.idempotent({ requestId, userId: context.user.id, organizationId: context.organizationId, method, url }, body, () => store.saveCollection({
            subjectId: subject.id,
            organizationId: envelope.organizationId,
            encryptedData: envelope.encryptedData,
            iv: envelope.iv,
            dataRegistro: clock.toISOString(),
            createdByUserId: context.user.id
          }));
          await sendAudit(store, context, 'school_collection.create', 'allowed');
          return response(201, { collection: result });
        }
      }

      if (method === 'GET' && path[1] === 'subjects' && path[2] && path[3] === undefined) {
        const subject = await subjectById(store, path[2]);
        if (subject.ownerUserId === context.user.id) {
          await sendAudit(store, context, 'subject.read', 'allowed');
          return response(200, subject);
        }
        const { grant } = await grantFor(store, context.user.id, subject.id, 'communication_profile.read', clock, context.user.organizationId);
        context.organizationId = grant.organizationId;
        await sendAudit(store, context, 'subject.read', 'allowed');
        return response(200, { id: subject.id, displayName: subject.displayName, status: subject.status });
      }

      if (method === 'GET' && path[1] === 'subjects' && path[2] && path[3] === 'grants') {
        const subject = await subjectById(store, path[2]);
        if (subject.ownerUserId !== context.user.id) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        const grants = await store.listRecords('grants', { subjectId: subject.id });
        await sendAudit(store, context, 'grant.read', 'allowed');
        return response(200, { grants });
      }

      if (method === 'POST' && path[1] === 'organizations' && path[3] === 'invitations') {
        context.organizationId = path[2];
        await requireScope(store, context.user.id, context.organizationId, 'access.invite', clock, context.user);
        const result = await store.idempotent({ requestId, userId: context.user.id, organizationId: context.organizationId, method, url }, body, async () => {
          const invitation = {
            id: `invite-${randomUUID()}`,
            organizationId: context.organizationId,
            inviteeUserId: body?.inviteeUserId,
            subjectId: body?.subjectId ?? null,
            consentId: body?.consentId ?? null,
            purpose: body?.purpose ?? null,
            scopes: Array.isArray(body?.scopes) ? [...new Set(body.scopes)] : [],
            role: body?.role ?? 'professional',
            status: 'pending',
            expiresAt: body?.expiresAt ?? '2099-01-01T00:00:00.000Z'
          };
          if (!invitation.inviteeUserId || !['professional', 'caregiver', 'org_admin'].includes(invitation.role) || !(new Date(invitation.expiresAt) > clock)) throw new AuthorizationError('INVALID_INVITATION', 400);
          if (!await store.findRecord('users', { id: invitation.inviteeUserId, status: 'active' })) throw new AuthorizationError('INVALID_INVITATION', 400);
          if (invitation.subjectId || invitation.consentId) {
            if (!invitation.subjectId || !invitation.consentId) throw new AuthorizationError('CONSENT_REQUIRED', 400);
            const consent = await activeConsent(store, invitation.consentId, clock);
            if (consent.subjectId !== invitation.subjectId || consent.organizationId !== invitation.organizationId || consent.recipientUserId !== invitation.inviteeUserId) throw new AuthorizationError('CONSENT_MISMATCH', 400);
          }
          await store.saveRecord('invitations', invitation);
          await sendAudit(store, context, 'invitation.create', 'allowed');
          return response(201, invitation);
        });
        return result;
      }

      if (method === 'GET' && path[1] === 'invitations' && path[2]) {
        const invitation = await store.findRecord('invitations', { id: path[2] });
        if (!invitation || invitation.inviteeUserId !== context.user.id) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        await sendAudit(store, context, 'invitation.read', 'allowed');
        return response(200, invitation);
      }

      if (method === 'POST' && path[1] === 'invitations' && path[2] && (path[3] === 'accept' || path[3] === 'decline')) {
        const invitation = await store.findRecord('invitations', { id: path[2] });
        if (!invitation || invitation.inviteeUserId !== context.user.id) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        if (invitation.status !== 'pending') throw new AuthorizationError('REVOKED');
        if (!(new Date(invitation.expiresAt) > clock)) throw new AuthorizationError('EXPIRED');
        if (path[3] === 'decline') {
          invitation.status = 'declined';
          await store.saveRecord('invitations', invitation);
          await sendAudit(store, context, 'invitation.decline', 'allowed');
          return response(200, invitation);
        }
        let consent = null;
        if (invitation.subjectId || invitation.consentId) {
          if (!invitation.subjectId || !invitation.consentId) throw new AuthorizationError('CONSENT_REQUIRED', 400);
          consent = await activeConsent(store, invitation.consentId, clock);
          if (consent.subjectId !== invitation.subjectId || consent.recipientUserId !== context.user.id || consent.organizationId !== invitation.organizationId) throw new AuthorizationError('CONSENT_MISMATCH', 400);
        }
        invitation.status = 'accepted';
        await store.saveRecord('invitations', invitation);
        const membership = { id: `membership-${invitation.id}`, userId: context.user.id, organizationId: invitation.organizationId, role: invitation.role, status: 'active', validUntil: invitation.expiresAt };
        if (!await store.findRecord('memberships', { userId: membership.userId, organizationId: membership.organizationId })) await store.saveRecord('memberships', membership);
        let grant = null;
        if (consent) {
          const relationship = { id: `relationship-${invitation.id}`, userId: context.user.id, subjectId: invitation.subjectId, organizationId: invitation.organizationId, role: invitation.role, status: 'active', validUntil: consent.validUntil };
          await store.saveRecord('relationships', relationship);
          grant = { id: `grant-${invitation.id}`, userId: context.user.id, subjectId: invitation.subjectId, organizationId: invitation.organizationId, consentId: consent.id, purpose: consent.purpose, scopes: consent.scopes, status: 'active', validUntil: consent.validUntil };
          await store.saveRecord('grants', grant);
        }
        await sendAudit(store, context, 'invitation.accept', 'allowed');
        return response(200, { invitation, membership, grant });
      }

      if (method === 'POST' && path[1] === 'subjects' && path[2] && path[3] === 'grants' && path[5] === 'revoke') {
        const subject = await subjectForOwner(store, path[2], context.user.id);
        const grant = await store.findRecord('grants', { id: path[4], subjectId: subject.id });
        if (!grant) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        grant.status = 'revoked';
        const consent = await store.findRecord('consents', { id: grant.consentId });
        if (consent) {
          consent.status = 'revoked';
          consent.revokedAt = clock.toISOString();
          await store.saveRecord('consents', consent);
        }
        await store.saveRecord('grants', grant);
        for (const relationship of await store.listRecords('relationships', { subjectId: subject.id, userId: grant.userId })) {
          relationship.status = 'revoked'; await store.saveRecord('relationships', relationship);
        }
        await sendAudit(store, context, 'grant.revoke', 'allowed');
        return response(200, { grant, consent });
      }

      if (method === 'GET' && path[1] === 'organizations' && path[3] === 'benefits') {
        context.organizationId = path[2];
        await requireScope(store, context.user.id, context.organizationId, 'benefit.read', clock, context.user);
        const benefits = await store.listRecords('benefits', { organizationId: context.organizationId });
        await sendAudit(store, context, 'benefit.read', 'allowed');
        return response(200, { benefits });
      }

      if (method === 'GET' && path[1] === 'organizations' && path[3] === 'audit-events') {
        context.organizationId = path[2];
        await requireScope(store, context.user.id, context.organizationId, 'audit.read', clock, context.user);
        return response(200, { events: await store.listRecords('auditEvents', { organizationId: context.organizationId }) });
      }

      return response(404, { error: 'NOT_FOUND' });
    } catch (rawError) {
      const error = stableError(rawError);
      if (context.user) await sendAudit(store, context, 'request.denied', 'denied', error);
      if (error.code === 'TOKEN_EXPIRED') {
        return response(401, { error: 'TOKEN_EXPIRED', code: 'TOKEN_EXPIRED', renewalRequired: true });
      }
      return response(error.status, { error: error.code });
    }
  }

  async function handle(request) {
    try { return await store.transaction(() => handleRequest(request)); }
    catch (_) { return response(500, { error: 'INTERNAL_ERROR' }); }
  }
  return { handle, store };
}

export { jsonHeaders };
