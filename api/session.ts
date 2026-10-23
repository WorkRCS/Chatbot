import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { clientIp, handleRouteError, json, preflight, readJson } from "../server/http";
import { createGuestId, issueGuestToken } from "../server/auth";
import { getDb } from "../server/db";
import { enforceRateLimit } from "../server/rate-limit";

const REFRESH_LIFETIME_DAYS = 180;

function hashRefreshToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function newRefreshToken(): string {
  return randomBytes(32).toString("base64url");
}

function constantTimeMatch(a: string, b: string): boolean {
  const aa = Buffer.from(a);
  const bb = Buffer.from(b);
  return aa.length === bb.length && timingSafeEqual(aa, bb);
}

export default async function handler(request: Request): Promise<Response> {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "POST") return json(request, { error: "Use POST." }, 405);

  try {
    await enforceRateLimit(clientIp(request), "session", 20, 60_000);
    const body = await readJson(request);
    const db = await getDb();
    const sessions = db.collection<any>("guest_sessions");
    const suppliedRefreshToken =
      typeof body.refreshToken === "string" &&
      /^[A-Za-z0-9_-]{40,80}$/.test(body.refreshToken)
        ? body.refreshToken
        : null;

    let guestId: string | null = null;
    if (suppliedRefreshToken) {
      const candidateHash = hashRefreshToken(suppliedRefreshToken);
      const existing = await sessions.findOne({
        refreshTokenHash: candidateHash,
        expiresAt: { $gt: new Date() },
      });

      // Constant-time check after lookup protects against accidental future non-hash comparisons.
      if (existing && typeof existing.refreshTokenHash === "string" &&
          constantTimeMatch(existing.refreshTokenHash, candidateHash)) {
        guestId = String(existing._id);
      }
    }

    if (!guestId) guestId = createGuestId();

    const refreshToken = newRefreshToken();
    const expiresAtDate = new Date(Date.now() + REFRESH_LIFETIME_DAYS * 24 * 60 * 60 * 1000);
    const token = issueGuestToken(guestId);

    await sessions.updateOne(
      { _id: guestId },
      {
        $set: {
          refreshTokenHash: hashRefreshToken(refreshToken),
          expiresAt: expiresAtDate,
          updatedAt: new Date(),
        },
        $setOnInsert: { createdAt: new Date() },
      },
      { upsert: true },
    );

    return json(request, {
      guestId,
      token: token.token,
      expiresAt: token.expiresAt,
      refreshToken,
      refreshExpiresAt: Math.floor(expiresAtDate.getTime() / 1000),
    });
  } catch (error) {
    return handleRouteError(request, error);
  }
}
