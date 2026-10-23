# AI Chat — Flutter + Vercel

Responsive Flutter AI chat app with a Vercel Serverless API, Groq streaming chat, Tavily search, Cloudflare FLUX image generation, and MongoDB Atlas conversation history. Firebase Authentication is not used; the app uses signed anonymous guest sessions.

## What is implemented

### Flutter
- Responsive desktop/tablet/mobile chat UI with light/dark themes.
- Streaming assistant messages and skeleton loading.
- Groq model picker (GPT-OSS 20B, GPT-OSS 120B, Qwen vision model).
- Markdown answers, math/LaTeX rendering, source links, Copy, Like/Dislike.
- Local image picker with image preview and vision requests.
- Automatic image-generation intent routing in chat, plus a dedicated image generation screen.
- Conversation history, guest session persistence, and local PDF export.
- Mock UI mode when `API_BASE_URL` is not configured at build time.

### Vercel API
- `POST /api/session`: signed 30-day guest session.
- `POST /api/chat`: SSE streaming Groq response, model fallback, optional Tavily search, message persistence.
- `POST /api/image`: Cloudflare Workers AI FLUX image generation; saves prompt and result metadata.
- `GET /api/assets?id=...`: guest-owned, short-lived signed URLs for private R2 images.
- `GET /api/conversations` and `GET /api/conversations?id=...`: conversation/message history.
- `POST /api/feedback`: like/dislike persistence.
- `GET /api/health`: reports which integrations are configured without exposing keys.
- MongoDB rate limiting, conversation summaries for longer context, and optional R2 image storage.

## Deployment

### 1. Deploy the API to Vercel
Import this GitHub repository into Vercel. The project uses Node.js/TypeScript Serverless Functions in the `api/` folder.

In **Vercel → Project → Settings → Environment Variables**, add the required values:

| Variable | Required? | Purpose |
|---|---|---|
| `SESSION_SECRET` | Yes | At least 32 random characters; signs guest-session tokens |
| `GROQ_API_KEY` | Yes | Chat and conversation-summary requests |
| `MONGODB_URI` | Yes | MongoDB Atlas connection string |
| `MONGODB_DB_NAME` | Recommended | Use `ai_chat` |
| `CLOUDFLARE_ACCOUNT_ID` | Yes for image generation | Cloudflare account ID |
| `CLOUDFLARE_API_TOKEN` | Yes for image generation | Token with Workers AI permissions |
| `TAVILY_API_KEY` | Optional | Enables fresh web search and source links |
| `R2_ACCESS_KEY_ID` | Optional, recommended for persistent images | R2 S3-compatible access key |
| `R2_SECRET_ACCESS_KEY` | Optional, recommended for persistent images | R2 S3-compatible secret |
| `R2_BUCKET_NAME` | Optional, recommended for persistent images | Existing R2 bucket name |
| `R2_PUBLIC_BASE_URL` | Optional | Public base URL if you deliberately expose generated images |
| `CORS_ALLOWED_ORIGINS` | Optional | Web origins, comma-separated; for example `https://your-app.example` |

Generate `SESSION_SECRET` locally with `openssl rand -base64 48`; paste the result directly into Vercel. Never commit real secrets, paste them into Flutter, or put them in a public repository.

**MongoDB Atlas:** create a database user, allow network access for Vercel (use the narrowest feasible allow-list; for initial testing some Atlas setups use `0.0.0.0/0`, which is less restrictive), and copy the application connection string. The API creates its common indexes at runtime.

**Cloudflare:** create an API token with Workers AI permissions. FLUX generation may consume paid/free allocation depending on the account's current quota and model pricing.

**R2:** chat image uploads and generated image binaries are retained across sessions only when R2 is configured. Without R2, the current upload can still be sent for vision and a generated image can still be downloaded immediately, but its binary cannot be restored from old history later. For private buckets, the API returns fresh, time-limited signed URLs. Add R2 settings if you want durable image history.

After adding or changing environment variables, redeploy so the functions receive them.

### 2. Configure the Flutter app with the Vercel URL
The API URL is a Flutter compile-time setting, not an API secret. Once Vercel provides the project URL, build/run Flutter with:

```bash
flutter create . --platforms=android,ios,web
flutter pub get

# Web preview
flutter run -d chrome --dart-define=API_BASE_URL=https://YOUR-PROJECT.vercel.app

# Android / iOS device or emulator
flutter run --dart-define=API_BASE_URL=https://YOUR-PROJECT.vercel.app
```

For a web production build:

```bash
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-PROJECT.vercel.app
```

The Vercel domain must be supplied to the Flutter build; adding it only to Vercel environment variables will not configure the client.

### 3. Verify the API
After deployment, open:

`https://YOUR-PROJECT.vercel.app/api/health`

The response lists boolean configuration flags only. It does not test every vendor credential with a live request. Start the app and try a short chat, an image-generation prompt, then a prompt that requests current information to test Tavily.

## Local backend checks

```bash
npm install
npm run typecheck
```

Install Flutter stable, then:

```bash
flutter create . --platforms=android,ios,web
flutter pub get
flutter analyze
flutter test
```

GitHub Actions runs the backend TypeScript check and Flutter analyzer on pushes and pull requests.

## Notes and current limitations
- No Firebase Authentication and no video-generation provider.
- Guest sessions are device-local; there is no account-based recovery or cross-device identity.
- Tavily search is optional; without `TAVILY_API_KEY`, current web-search results/citations are unavailable. The model is instructed not to claim current verification when no sources were returned.
- Groq model availability and free-tier limits are provider-controlled. Failover cannot guarantee sub-second response when the provider is rate-limited or unavailable.
- Long-conversation summaries are periodically updated through Groq; this is best-effort, not a perfect transcript retrieval system.
- PDF export is local to Flutter. Exact LaTeX fidelity and Bengali font embedding should be validated on target platforms.
- This repository includes implementation and CI configuration, but the app has not been deployed to your Vercel account and cannot make live provider calls until you configure your own keys and Flutter API URL.
