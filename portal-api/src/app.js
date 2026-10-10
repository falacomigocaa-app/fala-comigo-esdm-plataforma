import { AuthorizationError, audit, isFutureDate, membershipFor, requireScope, stableError } from './authorization.js';
import { authenticateRequest } from './middlewares/auth.middleware.js';
import { issueAccessToken } from './services/auth.service.js';
import { createStore, esdmTranslations, roleScopes } from './store.js';

const jsonHeaders = { 'content-type': 'application/json; charset=utf-8' };

function response(status, body) {
  return { status, body };
}

function parsePath(url) {
  return new URL(url, 'http://localhost').pathname.split('/').filter(Boolean);
}

function sendAudit(store, context, action, result, error = null) {
  audit(store, {
    userId: context.user?.id ?? null,
    organizationId: context.organizationId,
    action,
    result,
    code: error?.code ?? null,
    requestId: context.requestId,
    now: context.now
  });
}

function idempotencyKey(context, method, path, requestId) {
  return requestId ? JSON.stringify([context.user.id, context.user.organizationId, method, path, requestId]) : null;
}

async function idempotentAsync(store, key, body, handler) {
  if (!key) return handler();
  const fingerprint = JSON.stringify(body);
  const previous = store.idempotency.get(key);
  if (previous) {
    if (previous.fingerprint !== fingerprint) throw new AuthorizationError('IDEMPOTENCY_CONFLICT', 409);
    return structuredClone(await previous.result);
  }
  const entry = { fingerprint, result: Promise.resolve().then(handler).then((result) => structuredClone(result)) };
  store.idempotency.set(key, entry);
  try {
    return structuredClone(await entry.result);
  } catch (error) {
    if (store.idempotency.get(key) === entry) store.idempotency.delete(key);
    throw error;
  }
}

function subjectForOwner(store, subjectId, userId) {
  const subject = store.subjects.find((item) => item.id === subjectId && item.status === 'active');
  if (!subject || subject.ownerUserId !== userId) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
  return subject;
}

function subjectById(store, subjectId) {
  const subject = store.subjects.find((item) => item.id === subjectId && item.status === 'active');
  if (!subject) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
  return subject;
}

function activeConsent(store, consentId, now) {
  const consent = store.consents.find((item) => item.id === consentId);
  if (!consent) throw new AuthorizationError('CONSENT_REQUIRED');
  if (consent.status === 'revoked') throw new AuthorizationError('REVOKED');
  if (consent.status !== 'active' || !isFutureDate(consent.validUntil, now)) throw new AuthorizationError('EXPIRED');
  return consent;
}

function grantFor(store, userId, subjectId, scope, now, organizationId) {
  const grant = store.grants.find((item) => item.userId === userId && item.subjectId === subjectId && item.status === 'active' && item.organizationId === organizationId && item.scopes.includes(scope));
  if (!grant) throw new AuthorizationError('GRANT_REQUIRED');
  if (!isFutureDate(grant.validUntil, now)) throw new AuthorizationError('EXPIRED');
  const consent = activeConsent(store, grant.consentId, now);
  membershipFor(store, userId, organizationId, now);
  if (consent.subjectId !== subjectId || consent.organizationId !== organizationId ||
      consent.recipientUserId !== userId || consent.purpose !== grant.purpose || !consent.scopes.includes(scope)) {
    throw new AuthorizationError('CONSENT_MISMATCH');
  }
  return { grant, consent };
}

function subjectWithScope(store, subjectId, user, scope, now) {
  requireScope(store, user.id, user.organizationId, scope, now, user);
  const subject = subjectById(store, subjectId);
  if (subject.ownerUserId === user.id) return { subject, grant: null };
  const { grant } = grantFor(store, user.id, subjectId, scope, now, user.organizationId);
  return { subject, grant };
}

function requireGoalCode(code) {
  if (!code || !Object.hasOwn(esdmTranslations, code)) throw new AuthorizationError('INVALID_ESDM_CODE', 400);
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
      !isBase64(body?.iv) || decodedByteLength(body.iv) < 12) {
    throw new AuthorizationError('INVALID_E2EE_ENVELOPE', 400);
  }
  return {
    organizationId,
    encryptedData: body.encryptedData,
    iv: body.iv
  };
}

export function createApp({ store = createStore(), now = () => new Date() } = {}) {
  async function handle({ method, url, headers = {}, body = null }) {
    const path = parsePath(url);
    const requestId = headers['x-request-id'] ?? null;
    const clock = now();
    const context = { user: null, organizationId: null, requestId, now: clock };
    let operationKey;

    try {
      if (method === 'POST' && path[0] === 'v1' && path[1] === 'auth' && path[2] === 'login') {
        const claims = await store.authenticateCredentials(body ?? {}, clock);
        const accessToken = issueAccessToken(claims);
        const refreshToken = await store.createRefreshToken(claims, clock);
        const canReadKey = claims.scopes.includes('organization.key.read');
        const organizationKey = process.env.MASTER_CRYPTO_KEY && canReadKey
          ? await store.getOrganizationKey(claims.organizationId)
          : null;
        if (process.env.MASTER_CRYPTO_KEY && canReadKey && !organizationKey) {
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
        const currentClaims = await store.validateRefreshClaims(claims, clock);
        const user = store.users.find((candidate) => candidate.id === claims.userId && candidate.status === 'active');
        if (!user) throw new AuthorizationError('REFRESH_TOKEN_INVALID', 401);
        const accessToken = issueAccessToken(currentClaims);
        const refreshToken = await store.createRefreshToken(currentClaims, clock);
        return response(200, {
          accessToken,
          refreshToken,
          expiresIn: 15 * 60,
          refreshExpiresIn: 7 * 24 * 60 * 60
        });
      }

      if (method === 'GET' && path[0] === 'v1' && path[1] === 'me') {
        context.user = authenticateRequest(store, headers);
        return response(200, { id: context.user.id, status: context.user.status, storageMode: store.storageMode });
      }

      context.user = authenticateRequest(store, headers);
      context.organizationId = context.user.organizationId;
      operationKey = idempotencyKey(context, method, path, requestId);
      if (path[0] !== 'v1') return response(404, { error: 'NOT_FOUND' });

      if (method === 'GET' && path[1] === 'organizations' && path[3] === 'keys') {
        context.organizationId = path[2];
        requireScope(store, context.user.id, context.organizationId, 'organization.key.read', clock, context.user);
        const organizationKey = await store.getOrganizationKey(context.organizationId);
        if (!organizationKey) throw new AuthorizationError('ORGANIZATION_KEY_UNAVAILABLE', 404);
        sendAudit(store, context, 'organization.key.read', 'allowed');
        return response(200, organizationKey);
      }

      if (method === 'GET' && path[1] === 'organizations' && path[3] === undefined && path[2]) {
        context.organizationId = path[2];
        requireScope(store, context.user.id, context.organizationId, 'organization.read', clock, context.user);
        const organization = store.organizations.find((item) => item.id === context.organizationId);
        if (!organization) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        sendAudit(store, context, 'organization.read', 'allowed');
        return response(200, organization);
      }

      if (method === 'GET' && path[1] === 'organizations' && path[3] === 'memberships') {
        context.organizationId = path[2];
        requireScope(store, context.user.id, context.organizationId, 'membership.read', clock, context.user);
        const memberships = store.memberships.filter((item) => item.organizationId === context.organizationId);
        sendAudit(store, context, 'membership.read', 'allowed');
        return response(200, { memberships });
      }

      if (method === 'GET' && path[1] === 'organizations' && path[3] === 'subjects') {
        context.organizationId = path[2];
        requireScope(store, context.user.id, context.organizationId, 'access.read', clock, context.user);
        const subjects = store.subjects.filter((subject) => {
          if (subject.ownerUserId === context.user.id) return true;
          return store.grants.some((grant) => {
            if (grant.userId !== context.user.id || grant.organizationId !== context.organizationId || grant.subjectId !== subject.id) return false;
            return grant.scopes.some((scope) => {
              try {
                grantFor(store, context.user.id, subject.id, scope, clock, context.organizationId);
                return true;
              } catch (error) {
                if (error instanceof AuthorizationError) return false;
                throw error;
              }
            });
          });
        }).map((subject) => ({ id: subject.id, displayName: subject.displayName, status: subject.status, organizationId: context.organizationId }));
        sendAudit(store, context, 'subject.list', 'allowed');
        return response(200, { subjects });
      }

      if (method === 'POST' && path[1] === 'subjects' && path[2] && path[3] === 'consents') {
        const subject = subjectForOwner(store, path[2], context.user.id);
        const organizationId = body?.organizationId;
        const organization = store.organizations.find((item) => item.id === organizationId && item.status === 'active');
        if (!organization) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        const scopes = Array.isArray(body?.scopes) ? [...new Set(body.scopes)] : [];
        if (scopes.length === 0 || !body?.purpose || !body?.recipientUserId) throw new AuthorizationError('INVALID_CONSENT', 400);
        const validUntil = body.validUntil ?? '2099-01-01T00:00:00.000Z';
        if (!Number.isFinite(new Date(validUntil).getTime())) throw new AuthorizationError('INVALID_CONSENT', 400);
        if (!isFutureDate(validUntil, clock)) throw new AuthorizationError('EXPIRED');
        const consent = {
          id: `consent-${store.consents.length + 1}`,
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
        store.consents.push(consent);
        sendAudit(store, context, 'consent.create', 'allowed');
        return response(201, consent);
      }

      if (path[1] === 'subjects' && path[2] && (path[3] === 'esdm-goals' || path[3] === 'school-collections')) {
        const subjectId = path[2];
        const resource = path[3];
        const isGoal = resource === 'esdm-goals';
        const readScope = isGoal ? 'esdm_goal.read' : 'school_collection.read';
        const writeScope = isGoal ? 'esdm_goal.write' : 'school_collection.write';
        const { subject, grant } = subjectWithScope(store, subjectId, context.user, method === 'POST' ? writeScope : readScope, clock);
        context.organizationId = grant?.organizationId ?? context.user.organizationId;

        if (method === 'GET' && isGoal) {
          const goals = await store.getGoalsBySubject(subject.id);
          sendAudit(store, context, 'esdm_goal.read', 'allowed');
          return response(200, { goals });
        }
        if (method === 'POST' && isGoal) {
          const translation = requireGoalCode(body?.codigoTecnicoDenver);
          const result = await idempotentAsync(store, operationKey, body, () => store.saveGoal({
            subjectId: subject.id,
            codigoTecnicoDenver: body.codigoTecnicoDenver,
            status: body.status ?? 'Em Progresso',
            passoAtualAba: Number.isInteger(body.passoAtualAba) ? body.passoAtualAba : 1,
            createdByUserId: context.user.id
          }));
          sendAudit(store, context, 'esdm_goal.create', 'allowed');
          return response(201, { goal: { ...result, ...translation } });
        }
        if (method === 'GET' && !isGoal) {
          const collections = await store.getCollectionsBySubject(subject.id, context.user.organizationId);
          sendAudit(store, context, 'school_collection.read', 'allowed');
          return response(200, { collections });
        }
        if (method === 'POST' && !isGoal) {
          const envelope = requireEncryptedCollectionEnvelope(body, context.user.organizationId);
          const result = await idempotentAsync(store, operationKey, body, () => store.saveCollection({
            subjectId: subject.id,
            organizationId: envelope.organizationId,
            encryptedData: envelope.encryptedData,
            iv: envelope.iv,
            dataRegistro: clock.toISOString(),
            createdByUserId: context.user.id
          }));
          sendAudit(store, context, 'school_collection.create', 'allowed');
          return response(201, { collection: result });
        }
      }

      if (method === 'GET' && path[1] === 'subjects' && path[2] && path[3] === undefined) {
        const subject = subjectById(store, path[2]);
        if (subject.ownerUserId === context.user.id) {
          sendAudit(store, context, 'subject.read', 'allowed');
          return response(200, subject);
        }
        const { grant } = grantFor(store, context.user.id, subject.id, 'communication_profile.read', clock, context.user.organizationId);
        context.organizationId = grant.organizationId;
        sendAudit(store, context, 'subject.read', 'allowed');
        return response(200, { id: subject.id, displayName: subject.displayName, status: subject.status });
      }

      if (method === 'GET' && path[1] === 'subjects' && path[2] && path[3] === 'grants') {
        const subject = subjectById(store, path[2]);
        if (subject.ownerUserId !== context.user.id) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        const grants = store.grants.filter((item) => item.subjectId === subject.id);
        sendAudit(store, context, 'grant.read', 'allowed');
        return response(200, { grants });
      }

      if (method === 'POST' && path[1] === 'organizations' && path[3] === 'invitations') {
        context.organizationId = path[2];
        requireScope(store, context.user.id, context.organizationId, 'access.invite', clock, context.user);
        const result = await idempotentAsync(store, operationKey, body, () => {
          const invitation = {
            id: `invite-created-${store.invitations.length + 1}`,
            organizationId: context.organizationId,
            inviteeUserId: body?.inviteeUserId ?? 'user-invitee-alpha',
            subjectId: body?.subjectId ?? null,
            consentId: body?.consentId ?? null,
            purpose: body?.purpose ?? null,
            scopes: Array.isArray(body?.scopes) ? [...new Set(body.scopes)] : undefined,
            role: body?.role ?? 'professional',
            status: 'pending',
            expiresAt: body?.expiresAt ?? '2099-01-01T00:00:00.000Z'
          };
          if (!['org_admin', 'professional', 'caregiver'].includes(invitation.role) ||
              (body?.scopes !== undefined && !Array.isArray(body.scopes)) ||
              invitation.scopes?.some((scope) => !roleScopes[invitation.role].includes(scope))) {
            throw new AuthorizationError('INVALID_INVITATION', 400);
          }
          if (!isFutureDate(invitation.expiresAt, clock)) throw new AuthorizationError('INVALID_INVITATION', 400);
          if (invitation.subjectId || invitation.consentId) {
            if (!invitation.subjectId || !invitation.consentId) throw new AuthorizationError('CONSENT_REQUIRED', 400);
            const consent = activeConsent(store, invitation.consentId, clock);
            if (consent.subjectId !== invitation.subjectId || consent.organizationId !== invitation.organizationId || consent.recipientUserId !== invitation.inviteeUserId) throw new AuthorizationError('CONSENT_MISMATCH', 400);
          }
          store.invitations.push(invitation);
          sendAudit(store, context, 'invitation.create', 'allowed');
          return response(201, invitation);
        });
        return result;
      }

      if (method === 'GET' && path[1] === 'invitations' && path[2]) {
        const invitation = store.invitations.find((item) => item.id === path[2]);
        if (!invitation || invitation.inviteeUserId !== context.user.id) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        sendAudit(store, context, 'invitation.read', 'allowed');
        return response(200, invitation);
      }

      if (method === 'POST' && path[1] === 'invitations' && path[2] && (path[3] === 'accept' || path[3] === 'decline')) {
        const invitation = store.invitations.find((item) => item.id === path[2]);
        if (!invitation || invitation.inviteeUserId !== context.user.id) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        if (invitation.status !== 'pending') throw new AuthorizationError('REVOKED');
        if (!isFutureDate(invitation.expiresAt, clock)) throw new AuthorizationError('EXPIRED');
        if (path[3] === 'decline') {
          invitation.status = 'declined';
          sendAudit(store, context, 'invitation.decline', 'allowed');
          return response(200, invitation);
        }
        let consent = null;
        if (invitation.subjectId || invitation.consentId) {
          if (!invitation.subjectId || !invitation.consentId) throw new AuthorizationError('CONSENT_REQUIRED', 400);
          consent = activeConsent(store, invitation.consentId, clock);
          if (consent.subjectId !== invitation.subjectId || consent.recipientUserId !== context.user.id || consent.organizationId !== invitation.organizationId) throw new AuthorizationError('CONSENT_MISMATCH', 400);
        }
        const membershipValues = { userId: context.user.id, organizationId: invitation.organizationId, role: invitation.role, status: 'active', validUntil: invitation.expiresAt };
        let membership = store.memberships.find((item) => item.userId === context.user.id && item.organizationId === invitation.organizationId);
        if (membership?.role === 'owner') throw new AuthorizationError('SCOPE_DENIED');
        if (membership) Object.assign(membership, membershipValues);
        else {
          membership = { id: `membership-${invitation.id}`, ...membershipValues };
          store.memberships.push(membership);
        }
        if (Array.isArray(invitation.scopes)) membership.scopes = [...invitation.scopes];
        else delete membership.scopes;
        invitation.status = 'accepted';
        let grant = null;
        if (consent) {
          const relationship = { id: `relationship-${invitation.id}`, userId: context.user.id, subjectId: invitation.subjectId, organizationId: invitation.organizationId, role: invitation.role, status: 'active', validUntil: consent.validUntil };
          store.relationships.push(relationship);
          grant = { id: `grant-${invitation.id}`, userId: context.user.id, subjectId: invitation.subjectId, organizationId: invitation.organizationId, consentId: consent.id, purpose: consent.purpose, scopes: Array.isArray(invitation.scopes) ? consent.scopes.filter((scope) => invitation.scopes.includes(scope)) : [...consent.scopes], status: 'active', validUntil: consent.validUntil };
          store.grants.push(grant);
        }
        sendAudit(store, context, 'invitation.accept', 'allowed');
        return response(200, { invitation, membership, grant });
      }

      if (method === 'POST' && path[1] === 'subjects' && path[2] && path[3] === 'grants' && path[5] === 'revoke') {
        const subject = subjectForOwner(store, path[2], context.user.id);
        const grant = store.grants.find((item) => item.id === path[4] && item.subjectId === subject.id);
        if (!grant) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
        grant.status = 'revoked';
        const consent = store.consents.find((item) => item.id === grant.consentId);
        if (consent) {
          consent.status = 'revoked';
          consent.revokedAt = clock.toISOString();
        }
        for (const relationship of store.relationships.filter((item) => item.subjectId === subject.id && item.userId === grant.userId)) relationship.status = 'revoked';
        sendAudit(store, context, 'grant.revoke', 'allowed');
        return response(200, { grant, consent });
      }

      if (method === 'GET' && path[1] === 'organizations' && path[3] === 'benefits') {
        context.organizationId = path[2];
        requireScope(store, context.user.id, context.organizationId, 'benefit.read', clock, context.user);
        const benefits = store.benefits.filter((item) => item.organizationId === context.organizationId);
        sendAudit(store, context, 'benefit.read', 'allowed');
        return response(200, { benefits });
      }

      if (method === 'GET' && path[1] === 'organizations' && path[3] === 'audit-events') {
        context.organizationId = path[2];
        requireScope(store, context.user.id, context.organizationId, 'audit.read', clock, context.user);
        return response(200, { events: store.auditEvents.filter((item) => item.organizationId === context.organizationId) });
      }

      return response(404, { error: 'NOT_FOUND' });
    } catch (rawError) {
      const error = stableError(rawError);
      if (context.user) sendAudit(store, context, 'request.denied', 'denied', error);
      if (error.code === 'TOKEN_EXPIRED') {
        return response(401, { error: 'TOKEN_EXPIRED', code: 'TOKEN_EXPIRED', renewalRequired: true });
      }
      return response(error.status, { error: error.code });
    }
  }

  return { handle, store };
}

export { jsonHeaders };
