import { randomUUID } from 'node:crypto';
import { effectiveScopes } from './store.js';

export class AuthorizationError extends Error {
  constructor(code, status = 403) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

export async function authenticate(store, userId) {
  if (!userId) throw new AuthorizationError('AUTH_REQUIRED', 401);
  const user = await store.findRecord('users', { id: userId, status: 'active' });
  if (!user) throw new AuthorizationError('AUTH_REQUIRED', 401);
  return user;
}

export async function membershipFor(store, userId, organizationId, now) {
  const membership = await store.findRecord('memberships', { userId, organizationId });
  if (!membership) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
  if (membership.status === 'revoked') throw new AuthorizationError('REVOKED');
  if (membership.status !== 'active' || !(new Date(membership.validUntil) > now)) {
    throw new AuthorizationError('EXPIRED');
  }
  const organization = await store.findRecord('organizations', { id: organizationId, status: 'active' });
  if (!organization) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
  return membership;
}

export async function requireScope(store, userId, organizationId, scope, now, actor) {
  const membership = await membershipFor(store, userId, organizationId, now);
  const scopes = effectiveScopes(membership);
  if (actor && actor.organizationId !== organizationId) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
  if (actor && !actor.scopes.includes(scope)) throw new AuthorizationError('SCOPE_DENIED');
  if (!scopes.includes(scope)) throw new AuthorizationError('SCOPE_DENIED');
  return membership;
}

export async function audit(store, { userId, organizationId = null, action, result, code = null, requestId, now }) {
  if (organizationId && !await store.findRecord('organizations', { id: organizationId })) organizationId = null;
  await store.saveRecord('auditEvents', {
    id: `audit-${randomUUID()}`,
    userId,
    organizationId,
    action,
    result,
    code,
    requestId: requestId ?? null,
    occurredAt: now.toISOString(),
    apiVersion: 'v1'
  });
}

export function stableError(error) {
  if (error instanceof AuthorizationError) return error;
  return new AuthorizationError('INTERNAL_ERROR', 500);
}
