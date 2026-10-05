import { roleScopes } from './store.js';

export class AuthorizationError extends Error {
  constructor(code, status = 403) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

export function authenticate(store, userId) {
  if (!userId) throw new AuthorizationError('AUTH_REQUIRED', 401);
  const user = store.users.find((candidate) => candidate.id === userId && candidate.status === 'active');
  if (!user) throw new AuthorizationError('AUTH_REQUIRED', 401);
  return user;
}

export function membershipFor(store, userId, organizationId, now) {
  const membership = store.memberships.find((candidate) =>
    candidate.userId === userId && candidate.organizationId === organizationId
  );
  if (!membership) throw new AuthorizationError('RELATIONSHIP_REQUIRED');
  if (membership.status === 'revoked') throw new AuthorizationError('REVOKED');
  if (membership.status !== 'active' || new Date(membership.validUntil) <= now) {
    throw new AuthorizationError('EXPIRED');
  }
  return membership;
}

export function requireScope(store, userId, organizationId, scope, now) {
  const membership = membershipFor(store, userId, organizationId, now);
  const scopes = roleScopes[membership.role] ?? [];
  if (!scopes.includes(scope)) throw new AuthorizationError('SCOPE_DENIED');
  return membership;
}

export function audit(store, { userId, organizationId = null, action, result, code = null, requestId, now }) {
  store.auditEvents.push({
    id: `audit-${store.auditEvents.length + 1}`,
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
