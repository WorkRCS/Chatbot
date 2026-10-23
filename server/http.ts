export class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

export function corsHeaders(request: Request): Headers {
  const headers = new Headers();
  const configured = process.env.CORS_ALLOWED_ORIGINS?.trim();
  const origin = request.headers.get("origin");
  const allowList = (configured || "*")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);

  if (allowList.includes("*")) {
    headers.set("Access-Control-Allow-Origin", "*");
  } else if (origin && allowList.includes(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Vary", "Origin");
  }

  headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
  headers.set("Access-Control-Max-Age", "86400");
  headers.set("Cache-Control", "no-store");
  return headers;
}

export function json(request: Request, body: unknown, status = 200): Response {
  const headers = corsHeaders(request);
  headers.set("Content-Type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(body), { status, headers });
}

export function preflight(request: Request): Response | null {
  if (request.method !== "OPTIONS") return null;
  return new Response(null, { status: 204, headers: corsHeaders(request) });
}

export function methodNotAllowed(request: Request, allowed: string[]): Response {
  return json(request, { error: "Method not allowed. Use " + allowed.join(" or ") + "." }, 405);
}

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      throw new Error("Expected an object");
    }
    return value as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "Request body must be valid JSON.");
  }
}

export async function handleRouteError(request: Request, error: unknown): Promise<Response> {
  if (error instanceof HttpError) {
    return json(request, { error: error.message }, error.status);
  }

  const message = error instanceof Error ? error.message : "Unknown error";
  if (message.includes("SESSION_SECRET is not configured")) {
    return json(request, { error: "Backend setup is incomplete: SESSION_SECRET is missing." }, 503);
  }
  if (message.includes("MONGODB_URI is not configured")) {
    return json(request, { error: "Backend setup is incomplete: MONGODB_URI is missing." }, 503);
  }

  console.error("[api] request failed", error instanceof Error ? error.name : "UnknownError");
  return json(request, { error: "The request could not be completed. Check Vercel function logs." }, 500);
}

export function requireMethod(request: Request, expected: string): Response | null {
  if (request.method === "OPTIONS") return preflight(request);
  if (request.method !== expected) return methodNotAllowed(request, [expected]);
  return null;
}

export function clientIp(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for");
  return forwarded?.split(",")[0]?.trim().slice(0, 80) || "unknown";
}
