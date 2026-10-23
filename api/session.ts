import { clientIp, handleRouteError, json, preflight, readJson } from "../server/http";
import { createGuestId, issueGuestToken } from "../server/auth";
import { enforceRateLimit } from "../server/rate-limit";

export default async function handler(request: Request): Promise<Response> {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "POST") return json(request, { error: "Use POST." }, 405);

  try {
    await enforceRateLimit(clientIp(request), "session", 20, 60_000);
    const body = await readJson(request);
    const requestedId = typeof body.guestId === "string" ? body.guestId : "";
    const guestId =
      /^[a-zA-Z0-9_-]{20,80}$/.test(requestedId) ? requestedId : createGuestId();
    const session = issueGuestToken(guestId);
    return json(request, {
      guestId,
      token: session.token,
      expiresAt: session.expiresAt,
    });
  } catch (error) {
    return handleRouteError(request, error);
  }
}
