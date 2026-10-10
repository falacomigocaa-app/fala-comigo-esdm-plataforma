import test from 'node:test';
import assert from 'node:assert/strict';
import { apiClient } from '../src/api/client.js';
import { hydrateEscolaScreen } from '../src/screens/escola_screen.js';

test('school dashboard decrypts envelopes before summarizing independence', async () => {
  const rawKey = new Uint8Array(32).fill(41);
  const key = await crypto.subtle.importKey('raw', rawKey, { name: 'AES-GCM' }, false, ['encrypt']);
  const iv = new Uint8Array(12).fill(5);
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(JSON.stringify({ blocoRotinaEscolar: 'Lanche', nivelSuporte: 'Independente' })));
  const session = { userId: 'synthetic-user', subjectId: 'synthetic-subject', organizationId: 'synthetic-org', organizationKey: Buffer.from(rawKey).toString('base64') };
  const nodes = new Map();
  globalThis.document = { querySelector(selector) {
    if (!nodes.has(selector)) nodes.set(selector, { textContent: '', innerHTML: '', addEventListener() {} });
    return nodes.get(selector);
  } };
  const original = apiClient.carregarHistoricoEscolar;
  apiClient.carregarHistoricoEscolar = async () => ({ collections: [{ organizationId: session.organizationId, encryptedData: Buffer.from(encrypted).toString('base64'), iv: Buffer.from(iv).toString('base64'), dataRegistro: '2026-10-10T12:00:00Z' }] });
  try {
    await hydrateEscolaScreen({ session });
    assert.equal(nodes.get('[data-best-block]').textContent, 'Lanche');
    assert.match(nodes.get('[data-best-score]').innerHTML, /^3.0/);
    assert.match(nodes.get('[data-collections-body]').innerHTML, /Independente/);
    assert.doesNotMatch(nodes.get('[data-collections-body]').innerHTML, /undefined|NaN/);
  } finally {
    apiClient.carregarHistoricoEscolar = original;
    delete globalThis.document;
  }
});
