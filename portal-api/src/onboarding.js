import { randomBytes, randomUUID, createHash } from 'node:crypto';
import bcrypt from 'bcryptjs';
import { AuthorizationError, audit, membershipFor, requireScope } from './authorization.js';
import { authenticateRequest } from './middlewares/auth.middleware.js';
import { allowedScopes, effectiveScopes, roleScopes } from './store.js';

const clinicalScopes = ['esdm_goal.read', 'esdm_goal.write', 'school_collection.read', 'school_collection.write', 'routine.read'];
const roles = ['professional', 'teacher', 'caregiver', 'org_admin'];
const fail = (code, status = 400) => { throw new AuthorizationError(code, status); };
const tokenHash = (value) => createHash('sha256').update(value).digest('hex');
const validPassword = (value) => typeof value === 'string' && value.length >= 16 && Buffer.byteLength(value, 'utf8') <= 72;
function deadline(value, now, maximumDays = 366) {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || date <= now || date > new Date(now.getTime() + maximumDays * 86400000)) fail('INVALID_EXPIRY');
  return date.toISOString();
}
function selectedScopes(body, role, actor) {
  const requested = Array.isArray(body.scopes) ? [...new Set(body.scopes)] : roleScopes[role];
  if (!requested || requested.some((scope) => !allowedScopes(role).includes(scope) || !actor.scopes.includes(scope))) fail('INVALID_SCOPES');
  // A membership can identify its own organization and list only authorized patients.
  return [...new Set(['organization.read', 'access.read', ...requested])].filter((scope) => allowedScopes(role).includes(scope));
}

export async function handleOnboarding({ store, method, path, headers, body, context }) {
  if (path[0] !== 'v1') return null;
  const now = context.now;
  if (method === 'POST' && path.join('/') === 'v1/auth/activate') {
    if (typeof body?.token !== 'string' || !/^[a-f0-9]{64}$/.test(body.token) || !validPassword(body?.password)) fail('INVALID_ACTIVATION');
    const initial = await store.findRecord('activationTokens', { id: tokenHash(body.token) });
    if (!initial) fail('INVALID_ACTIVATION');
    return store.withLock(`invitation:${initial.invitationId}`, async () => {
      const token = await store.findRecord('activationTokens', { id: tokenHash(body.token) });
      if (!token || token.usedAt || new Date(token.expiresAt) <= now) fail('INVALID_ACTIVATION');
      const invitation = await store.findRecord('invitations', { id: token.invitationId, status: 'pending' });
      const user = await store.findRecord('users', { id: token.userId, status: 'disabled' });
      if (!invitation || !user || new Date(invitation.expiresAt) <= now || !await store.findRecord('organizations', { id: invitation.organizationId, status: 'active' })) fail('INVALID_ACTIVATION');
      await store.saveRecord('users', { ...user, passwordHash: await bcrypt.hash(body.password, 12), status: 'active', updatedAt: now.toISOString() });
      await store.saveRecord('memberships', { id: `membership-${invitation.id}`, userId: user.id, organizationId: invitation.organizationId, role: invitation.role, scopes: invitation.scopes, status: 'active', validUntil: new Date(now.getTime() + 365 * 86400000).toISOString() });
      await store.saveRecord('invitations', { ...invitation, status: 'accepted' });
      await store.saveRecord('activationTokens', { ...token, usedAt: now.toISOString() });
      await audit(store, { userId: user.id, organizationId: invitation.organizationId, action: 'account.activate', result: 'allowed', now });
      return { status: 200, body: { activated: true } };
    });
  }

  const organizationRoute = path[1] === 'organizations' && path.length >= 4 && ['account-invitations', 'people', 'member-access'].includes(path[3]);
  const subjectRoute = path[1] === 'subjects' && ((path.length === 2 && method === 'POST') || (path.length === 4 && path[3] === 'access'));
  const passwordRoute = method === 'POST' && path.join('/') === 'v1/auth/password';
  if (!organizationRoute && !subjectRoute && !passwordRoute) return null;
  context.user = await authenticateRequest(store, headers);
  const actor = context.user;
  const current = await membershipFor(store, actor.id, actor.organizationId, now);
  actor.scopes = actor.scopes.filter((scope) => effectiveScopes(current).includes(scope));
  context.organizationId = actor.organizationId;
  const orgId = organizationRoute ? path[2] : actor.organizationId;
  const recordAudit = (action) => audit(store, { userId: actor.id, organizationId: orgId, action, result: 'allowed', now });

  if (passwordRoute) {
    if (!validPassword(body?.password) || typeof body?.currentPassword !== 'string' || !await bcrypt.compare(body.currentPassword, actor.passwordHash)) fail('INVALID_PASSWORD');
    const user = await store.findRecord('users', { id: actor.id });
    await store.saveRecord('users', { ...user, passwordHash: await bcrypt.hash(body.password, 12), updatedAt: now.toISOString() });
    if (store.pool) await store.database.query('delete from refresh_tokens where user_id=$1', [actor.id]);
    else for (const [key, token] of store.refreshTokens) if (token.userId === actor.id) store.refreshTokens.delete(key);
    await recordAudit('account.password.change');
    return { status: 200, body: { changed: true } };
  }

  if (organizationRoute && path[3] === 'people' && method === 'GET') {
    await requireScope(store, actor.id, orgId, 'access.read', now, actor);
    const members = await store.listRecords('memberships', { organizationId: orgId, status: 'active' });
    const people = [];
    for (const member of members) {
      if (new Date(member.validUntil) <= now) continue;
      const user = await store.findRecord('users', { id: member.userId, status: 'active' });
      if (user) people.push({ id: user.id, email: user.email, role: member.role, scopes: effectiveScopes(member) });
    }
    await recordAudit('organization.people.read');
    return { status: 200, body: { people } };
  }

  if (organizationRoute && path[3] === 'account-invitations' && method === 'GET') {
    await requireScope(store, actor.id, orgId, 'access.invite', now, actor);
    const invitations = [];
    for (const invitation of await store.listRecords('invitations', { organizationId: orgId })) {
      const user = await store.findRecord('users', { id: invitation.inviteeUserId, status: 'disabled' });
      if (user) invitations.push({ id: invitation.id, email: user.email, status: invitation.status, expiresAt: invitation.expiresAt });
    }
    return { status: 200, body: { invitations } };
  }
  if (organizationRoute && path[3] === 'account-invitations' && path.length === 6 && path[5] === 'reissue' && method === 'POST') {
    await requireScope(store, actor.id, orgId, 'access.invite', now, actor);
    return store.withLock(`invitation:${path[4]}`, async () => {
      const invitation = await store.findRecord('invitations', { id: path[4], organizationId: orgId });
      if (!invitation || !await store.findRecord('users', { id: invitation.inviteeUserId, status: 'disabled' })) fail('INVALID_INVITATION');
      // A delegated admin may not renew privileges they no longer possess.
      if ((invitation.scopes ?? []).some((scope) => !actor.scopes.includes(scope))) fail('INVALID_SCOPES');
      for (const old of await store.listRecords('activationTokens', { invitationId: invitation.id })) await store.saveRecord('activationTokens', { ...old, usedAt: now.toISOString() });
      const token = randomBytes(32).toString('hex');
      const expiresAt = new Date(now.getTime() + 7 * 86400000).toISOString();
      await store.saveRecord('invitations', { ...invitation, status: 'pending', expiresAt });
      await store.saveRecord('activationTokens', { id: tokenHash(token), invitationId: invitation.id, userId: invitation.inviteeUserId, expiresAt, usedAt: null });
      await recordAudit('account.invite.reissue');
      return { status: 201, body: { id: invitation.id, token, expiresAt } };
    });
  }

  if (organizationRoute && path[3] === 'account-invitations' && path.length === 4 && method === 'POST') {
    await requireScope(store, actor.id, orgId, 'access.invite', now, actor);
    const email = typeof body?.email === 'string' ? body.email.trim().toLowerCase() : '';
    const role = body?.role;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 || !roles.includes(role)) fail('INVALID_INVITATION');
    const scopes = selectedScopes(body, role, actor);
    return store.withLock(`account:${email}`, async () => {
      if (await store.findRecord('users', { email })) fail('ACCOUNT_EXISTS', 409);
      const userId = `user-${randomUUID()}`;
      const expiresAt = new Date(now.getTime() + 7 * 86400000).toISOString();
      const invitation = { id: `invite-${randomUUID()}`, organizationId: orgId, inviteeUserId: userId, role, scopes, status: 'pending', expiresAt };
      const token = randomBytes(32).toString('hex');
      await store.saveRecord('users', { id: userId, externalSubject: `local:${userId}`, email, status: 'disabled' });
      await store.saveRecord('invitations', invitation);
      await store.saveRecord('activationTokens', { id: tokenHash(token), invitationId: invitation.id, userId, expiresAt, usedAt: null });
      await recordAudit('account.invite');
      // Return once to the authorized inviter; the secret never enters logs or the database.
      return { status: 201, body: { id: invitation.id, token, expiresAt } };
    });
  }

  if (organizationRoute && path[3] === 'member-access' && path[4] && method === 'POST') {
    await requireScope(store, actor.id, orgId, 'access.invite', now, actor);
    const member = await store.findRecord('memberships', { id: path[4], organizationId: orgId });
    if (!member || member.userId === actor.id || member.role === 'owner') fail('MEMBERSHIP_PROTECTED', 403);
    const role = body?.role ?? member.role;
    if (!roles.includes(role) || !['active', 'revoked'].includes(body?.status)) fail('INVALID_MEMBERSHIP');
    const scopes = selectedScopes(body, role, actor);
    const updated = { ...member, role, scopes, status: body.status, validUntil: deadline(body.validUntil, now) };
    await store.saveRecord('memberships', updated);
    await recordAudit('membership.update');
    return { status: 200, body: { membership: updated } };
  }

  if (path[1] === 'subjects' && path.length === 2 && method === 'POST') {
    await requireScope(store, actor.id, orgId, 'subject.create', now, actor);
    const name = typeof body?.displayName === 'string' ? body.displayName.trim() : '';
    if (!name || name.length > 80 || body?.guardianConfirmed !== true) fail('GUARDIAN_CONFIRMATION_REQUIRED');
    const subject = { id: `subject-${randomUUID()}`, familySpaceId: `family-${actor.id}`, ownerUserId: actor.id, displayName: name, status: 'active', createdAt: now.toISOString() };
    await store.saveRecord('subjects', subject);
    await recordAudit('subject.create');
    return { status: 201, body: { subject } };
  }

  if (subjectRoute && path[3] === 'access') {
    await requireScope(store, actor.id, orgId, 'access.read', now, actor);
    const subject = await store.findRecord('subjects', { id: path[2], status: 'active', ownerUserId: actor.id });
    if (!subject) fail('RELATIONSHIP_REQUIRED', 403);
    if (method === 'GET') {
      return { status: 200, body: { grants: await store.listRecords('grants', { subjectId: subject.id }) } };
    }
    if (method === 'POST') {
      if (body?.consentConfirmed !== true || typeof body?.purpose !== 'string' || !body.purpose.trim() || body.purpose.length > 300) fail('CONSENT_REQUIRED');
      const recipient = await membershipFor(store, body.recipientUserId, orgId, now);
      const scopes = Array.isArray(body.scopes) ? [...new Set(body.scopes)] : [];
      if (!scopes.length || scopes.some((scope) => !clinicalScopes.includes(scope) || !effectiveScopes(recipient).includes(scope))) fail('INVALID_SCOPES');
      const validUntil = deadline(body.validUntil, now);
      const consent = { id: `consent-${randomUUID()}`, subjectId: subject.id, organizationId: orgId, grantedByUserId: actor.id, recipientUserId: recipient.userId, purpose: body.purpose.trim(), scopes, noticeVersion: 'portal-consent-v1', status: 'active', validUntil, createdAt: now.toISOString(), revokedAt: null };
      const grant = { id: `grant-${randomUUID()}`, userId: recipient.userId, subjectId: subject.id, organizationId: orgId, consentId: consent.id, purpose: consent.purpose, scopes, status: 'active', validUntil };
      await store.saveRecord('consents', consent);
      await store.saveRecord('grants', grant);
      await recordAudit('consent.grant');
      return { status: 201, body: { grant } };
    }
  }
  return { status: 405, body: { error: 'METHOD_NOT_ALLOWED' } };
}
