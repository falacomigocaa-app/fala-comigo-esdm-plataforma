// Explicit operator bootstrap. Requires private environment input; prints no credentials.
import bcrypt from 'bcryptjs';
import { randomUUID } from 'node:crypto';
import { createStore } from '../src/store.js';
const { ADMIN_EMAIL, ADMIN_PASSWORD, ORGANIZATION_ID, ORGANIZATION_NAME, MASTER_CRYPTO_KEY, DATABASE_URL } = process.env;
if (!DATABASE_URL || !ADMIN_EMAIL || !ADMIN_PASSWORD || ADMIN_PASSWORD.length < 16 || !ORGANIZATION_ID || !ORGANIZATION_NAME || !MASTER_CRYPTO_KEY) throw new Error('Provide database, master key, organization and admin credentials privately (password >=16 characters)');
const store = createStore();
try {
  await store.transaction(async () => {
    const email = ADMIN_EMAIL.trim().toLowerCase();
    if (await store.findRecord('users', { email })) throw new Error('Account already exists; bootstrap will not overwrite it');
    const userId = `user-${randomUUID()}`;
    if (!await store.findRecord('organizations', { id: ORGANIZATION_ID })) await store.saveRecord('organizations', { id: ORGANIZATION_ID, name: ORGANIZATION_NAME, type: 'clinic', status: 'active' });
    await store.saveRecord('users', { id: userId, email, passwordHash: await bcrypt.hash(ADMIN_PASSWORD, 12), externalSubject: `local:${userId}`, status: 'active' });
    await store.saveRecord('memberships', { id: `membership-${randomUUID()}`, userId, organizationId: ORGANIZATION_ID, role: 'owner', status: 'active', validUntil: new Date(Date.now() + 365 * 86400000).toISOString() });
    if (!await store.getOrganizationKey(ORGANIZATION_ID)) await store.provisionOrganizationKey({ organizationId: ORGANIZATION_ID, createdByUserId: userId });
  });
  console.log('Organization administrator provisioned. No demo records were created.');
} finally { await store.pool.end(); }
