import { AuthorizationError } from '../authorization.js';
import { verifyAccessToken } from '../services/auth.service.js';

function bearerToken(headers = {}) {
  const authorization = headers.authorization ?? headers.Authorization;
  if (typeof authorization !== 'string') return null;
  const match = authorization.match(/^Bearer\s+([^\s]+)$/i);
  return match?.[1] ?? null;
}

function validatedClaims(payload) {
  if (
    !payload ||
    typeof payload.userId !== 'string' ||
    typeof payload.organizationId !== 'string' ||
    !Array.isArray(payload.scopes) ||
    payload.scopes.some((scope) => typeof scope !== 'string')
  ) {
    throw new AuthorizationError('INVALID_TOKEN', 401);
  }
  return {
    userId: payload.userId,
    organizationId: payload.organizationId,
    scopes: [...new Set(payload.scopes)],
    iat: payload.iat,
    exp: payload.exp
  };
}

export function authenticateRequest(store, headers = {}) {
  const token = bearerToken(headers);
  if (!token) throw new AuthorizationError('AUTH_REQUIRED', 401);

  try {
    const claims = validatedClaims(verifyAccessToken(token));
    const user = store.users.find((candidate) => candidate.id === claims.userId && candidate.status === 'active');
    if (!user) throw new AuthorizationError('AUTH_REQUIRED', 401);
    return { ...user, organizationId: claims.organizationId, scopes: claims.scopes, tokenIssuedAt: claims.iat, tokenExpiresAt: claims.exp };
  } catch (error) {
    if (error instanceof AuthorizationError) throw error;
    if (error?.name === 'TokenExpiredError') throw new AuthorizationError('TOKEN_EXPIRED', 401);
    throw new AuthorizationError('INVALID_TOKEN', 401);
  }
}

/** Express-compatible adapter for deployments that expose the same auth layer through Express. */
export function createAuthMiddleware(store) {
  return (req, res, next) => {
    try {
      req.user = authenticateRequest(store, req.headers);
      next();
    } catch (error) {
      const status = error.status ?? 401;
      const code = error.code ?? 'INVALID_TOKEN';
      res.status(status).json({ error: code, code, renewalRequired: code === 'TOKEN_EXPIRED' });
    }
  };
}
