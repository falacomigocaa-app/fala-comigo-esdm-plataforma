import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

const ALGORITHM = 'aes-256-gcm';
const KEY_BYTES = 32;
const IV_BYTES = 12;

export class OrganizationKeyError extends Error {
  constructor(code = 'ORGANIZATION_KEY_UNAVAILABLE') {
    super(code);
    this.name = 'OrganizationKeyError';
    this.code = code;
  }
}

function masterKey() {
  const encoded = process.env.MASTER_CRYPTO_KEY?.trim();
  if (!encoded) throw new OrganizationKeyError('MASTER_CRYPTO_KEY_REQUIRED');
  try {
    const raw = /^[0-9a-f]{64}$/i.test(encoded)
      ? Buffer.from(encoded, 'hex')
      : Buffer.from(encoded, 'base64');
    if (raw.length !== KEY_BYTES) throw new Error('invalid master key length');
    return raw;
  } catch (_) {
    throw new OrganizationKeyError('MASTER_CRYPTO_KEY_INVALID');
  }
}

function ensureOrganizationKey(rawKey) {
  const key = Buffer.isBuffer(rawKey) ? rawKey : Buffer.from(rawKey ?? []);
  if (key.length !== KEY_BYTES) throw new OrganizationKeyError('ORGANIZATION_KEY_INVALID');
  return key;
}

export function generateOrganizationKey() {
  return randomBytes(KEY_BYTES);
}

export function encryptOrganizationKey(rawKey, { organizationId = null, now = new Date() } = {}) {
  const key = ensureOrganizationKey(rawKey);
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv(ALGORITHM, masterKey(), iv);
  if (organizationId) cipher.setAAD(Buffer.from(organizationId, 'utf8'));
  const ciphertext = Buffer.concat([cipher.update(key), cipher.final()]);
  return JSON.stringify({
    version: 1,
    algorithm: ALGORITHM,
    iv: iv.toString('base64'),
    ciphertext: ciphertext.toString('base64'),
    authTag: cipher.getAuthTag().toString('base64'),
    organizationId,
    encryptedAt: now.toISOString()
  });
}

export function decryptOrganizationKey(encryptedValue, { organizationId = null } = {}) {
  if (typeof encryptedValue !== 'string') throw new OrganizationKeyError();
  try {
    const envelope = JSON.parse(encryptedValue);
    if (envelope.version !== 1 || envelope.algorithm !== ALGORITHM) throw new Error('unsupported envelope');
    const iv = Buffer.from(envelope.iv, 'base64');
    const ciphertext = Buffer.from(envelope.ciphertext, 'base64');
    const authTag = Buffer.from(envelope.authTag, 'base64');
    if (envelope.organizationId !== organizationId) throw new Error('organization binding mismatch');
    if (iv.length !== IV_BYTES || authTag.length !== 16 || ciphertext.length !== KEY_BYTES) throw new Error('invalid envelope');
    const decipher = createDecipheriv(ALGORITHM, masterKey(), iv);
    if (organizationId) decipher.setAAD(Buffer.from(organizationId, 'utf8'));
    decipher.setAuthTag(authTag);
    return ensureOrganizationKey(Buffer.concat([decipher.update(ciphertext), decipher.final()]));
  } catch (error) {
    if (error instanceof OrganizationKeyError) throw error;
    throw new OrganizationKeyError('ORGANIZATION_KEY_INVALID');
  }
}

export function organizationKeyToBase64(rawKey) {
  return ensureOrganizationKey(rawKey).toString('base64');
}
