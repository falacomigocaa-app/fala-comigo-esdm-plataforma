import jwt from 'jsonwebtoken';

export const DEFAULT_TOKEN_EXPIRATION = '15m';

function jwtSecret() {
  const secret = process.env.JWT_SECRET;
  if (!secret || secret.length < 32) {
    throw new Error('JWT_SECRET must be configured with at least 32 characters');
  }
  return secret;
}

function validateClaims({ userId, organizationId, scopes }) {
  if (!userId || typeof userId !== 'string') {
    throw new TypeError('userId is required to issue an access token');
  }
  if (!organizationId || typeof organizationId !== 'string') {
    throw new TypeError('organizationId is required to issue an access token');
  }
  if (!Array.isArray(scopes) || scopes.some((scope) => typeof scope !== 'string')) {
    throw new TypeError('scopes must be an array of strings');
  }
}

export function issueAccessToken({ userId, organizationId, scopes }, options = {}) {
  validateClaims({ userId, organizationId, scopes });
  return jwt.sign(
    { userId, organizationId, scopes: [...new Set(scopes)] },
    jwtSecret(),
    {
      expiresIn: options.expiresIn ?? DEFAULT_TOKEN_EXPIRATION,
      issuer: options.issuer ?? 'fala-comigo-portal-api',
      audience: options.audience ?? 'fala-comigo-clients'
    }
  );
}

export function verifyAccessToken(token, options = {}) {
  if (!token || typeof token !== 'string') {
    throw new Error('AUTH_REQUIRED');
  }
  return jwt.verify(token, jwtSecret(), {
    issuer: options.issuer ?? 'fala-comigo-portal-api',
    audience: options.audience ?? 'fala-comigo-clients'
  });
}
