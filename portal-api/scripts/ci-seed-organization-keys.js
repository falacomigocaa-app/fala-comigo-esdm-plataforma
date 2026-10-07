import { createStore } from '../src/store.js';

const store = createStore();
try {
  for (const organizationId of ['org-demo-alpha', 'org-demo-beta']) {
    await store.provisionOrganizationKey({
      organizationId,
      createdByUserId: organizationId === 'org-demo-alpha' ? 'user-admin-alpha' : 'user-admin-beta',
      now: new Date('2026-10-06T00:00:00.000Z')
    });
  }
  console.log('[ci-seed-organization-keys] organization keys provisioned');
} finally {
  await store.pool?.end();
}
