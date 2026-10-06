const DECODE_ERROR_MESSAGE = 'Erro de Decodificação: Chave de Organização inválida';

export class WebE2EEError extends Error {
  constructor(message = DECODE_ERROR_MESSAGE) {
    super(message);
    this.name = 'WebE2EEError';
    this.code = 'E2EE_KEY_INVALID';
  }
}

function base64ToBytes(value) {
  if (typeof value !== 'string' || value.length === 0) throw new WebE2EEError();
  try {
    const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
    const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=');
    const binary = globalThis.atob(padded);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch (_) {
    throw new WebE2EEError();
  }
}

function organizationKeyValue(session, organizationId) {
  const keys = session?.organizationKeys ?? session?.e2eeKeys ?? {};
  return keys[organizationId] ?? (session?.organizationId === organizationId ? session?.organizationKey : null);
}

function subtleCrypto(cryptoRef = globalThis.crypto) {
  if (!cryptoRef?.subtle) throw new WebE2EEError();
  return cryptoRef.subtle;
}

export async function importOrganizationKey({ organizationId, session, cryptoRef = globalThis.crypto } = {}) {
  if (!organizationId || session?.organizationId !== organizationId) throw new WebE2EEError();
  const encodedKey = organizationKeyValue(session, organizationId);
  const rawKey = base64ToBytes(encodedKey);
  if (rawKey.byteLength !== 32) throw new WebE2EEError();
  try {
    return await subtleCrypto(cryptoRef).importKey('raw', rawKey, { name: 'AES-GCM' }, false, ['decrypt']);
  } catch (_) {
    throw new WebE2EEError();
  }
}

export async function decryptE2EEEnvelope(envelope, { session, cryptoRef = globalThis.crypto } = {}) {
  if (!envelope || envelope.organizationId !== session?.organizationId) throw new WebE2EEError();
  const key = await importOrganizationKey({ organizationId: envelope.organizationId, session, cryptoRef });
  const iv = base64ToBytes(envelope.iv);
  const encryptedData = base64ToBytes(envelope.encryptedData);
  if (iv.byteLength !== 12 || encryptedData.byteLength <= 16) throw new WebE2EEError();
  try {
    const plaintext = await subtleCrypto(cryptoRef).decrypt({ name: 'AES-GCM', iv }, key, encryptedData);
    const decoded = new TextDecoder().decode(plaintext);
    const payload = JSON.parse(decoded);
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new WebE2EEError();
    return payload;
  } catch (error) {
    if (error instanceof WebE2EEError) throw error;
    throw new WebE2EEError();
  }
}

export async function decryptCollectionEnvelopes(collections, options = {}) {
  if (!Array.isArray(collections)) throw new WebE2EEError();
  return Promise.all(collections.map(async (collection) => {
    if (!collection?.encryptedData || !collection?.iv) return collection;
    const payload = await decryptE2EEEnvelope(collection, options);
    return { ...collection, ...payload, organizationId: collection.organizationId };
  }));
}

export { DECODE_ERROR_MESSAGE };
