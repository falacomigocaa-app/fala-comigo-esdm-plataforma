// Local development only. Never provision shared/demo passwords in production.
import { createStore } from '../src/store.js';
if (process.env.NODE_ENV === 'production' || process.env.ALLOW_DEMO_SEED !== '1' || !process.env.DATABASE_URL) {
  throw new Error('Synthetic seed requires a disposable DATABASE_URL and ALLOW_DEMO_SEED=1 outside production');
}
const local = new URL(process.env.DATABASE_URL);
if (!['localhost', '127.0.0.1', '[::1]'].includes(local.hostname)) throw new Error('Demo seed is restricted to a local database');
const target = createStore();
const source = createStore({ pool: null, fixtures: true });
try {
  await target.transaction(async () => {
    for (const kind of ['users', 'organizations', 'memberships', 'subjects', 'consents', 'invitations', 'grants', 'benefits']) {
      for (const record of source[kind]) await target.saveRecord(kind, record);
    }
  });
  console.log('Local synthetic authorization fixtures ready.');
} finally { await target.pool.end(); }
