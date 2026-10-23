import { createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { HttpError } from "./http";

const TOKEN_LIFETIME_SECONDS = 60 * 60 * 24 * 30;

function getSecret(): string {
  const secret = process.env.SESSION_SECRET;
  if (!secret || secret.length < 32) {
    throw new Error("SESSION_SECRET is not configured or is too short");
  }
  return secret;
}

function sign(value: string): string {
  return createHmac("sha256", getSecret()).update(value).digest("base64url");
}

export function createGuestId(): string {
  return randomUUID();
}

export function issueGuestToken(guestId: string): { token: string; expiresAt: number } {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(
    JSON.stringify({
      sub: guestId,
      iss: "ai-chat-backend",
      iat: now,
      exp: now + TOKEN_LIFETIME_SECONDS,
    }),
  ).toString("base64url");
  const unsigned = header + "." + payload;
  return {
    token: unsigned + "." + sign(unsigned),
    expiresAt: now + TOKEN_LIFETIME_SECONDS,
  };
}

export function verifyGuestToken(token: string): string {
  const parts = token.split(".");
  if (parts.length !== 3) throw new HttpError(401, "Session expired. Please retry.");

  const unsigned = parts[0] + "." + parts[1];
  const expected = Buffer.from(sign(unsigned));
  const actual = Buffer.from(parts[2]);
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    throw new HttpError(401, "Invalid guest session. Please restart the app.");
  }

  try {
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")) as {
      sub?: unknown;
      iss?: unknown;
      exp?: unknown;
    };
    if (
      payload.iss !== "ai-chat-backend" ||
      typeof payload.sub !== "string" ||
      !/^[a-zA-Z0-9_-]{20,80}$/.test(payload.sub) ||
      typeof payload.exp !== "number" ||
      payload.exp <= Math.floor(Date.now() / 1000)
    ) {
      throw new Error("Invalid claims");
    }
    return payload.sub;
  } catch {
    throw new HttpError(401, "Invalid or expired guest session. Please retry.");
  }
}

export function guestIdFromRequest(request: Request): string {
  const authorization = request.headers.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new HttpError(401, "Missing guest session. Please start a session first.");
  return verifyGuestToken(match[1]);
}
