import { json, preflight } from "../server/http";

export default async function handler(request: Request): Promise<Response> {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "GET") return json(request, { error: "Use GET." }, 405);

  return json(request, {
    ok: true,
    service: "ai-chat-backend",
    timestamp: new Date().toISOString(),
    configured: {
      sessionSecret: Boolean(process.env.SESSION_SECRET && process.env.SESSION_SECRET.length >= 32),
      groq: Boolean(process.env.GROQ_API_KEY),
      mongo: Boolean(process.env.MONGODB_URI),
      cloudflareAI: Boolean(process.env.CLOUDFLARE_ACCOUNT_ID && process.env.CLOUDFLARE_API_TOKEN),
      tavily: Boolean(process.env.TAVILY_API_KEY),
      r2: Boolean(
        process.env.R2_ACCESS_KEY_ID &&
        process.env.R2_SECRET_ACCESS_KEY &&
        process.env.R2_BUCKET_NAME,
      ),
    },
  });
}
