import { randomUUID } from "node:crypto";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { GetObjectCommand } from "@aws-sdk/client-s3";
import { guestIdFromRequest } from "../server/auth";
import { getDb } from "../server/db";
import { enforceRateLimit } from "../server/rate-limit";
import { handleRouteError, HttpError, json, preflight, readJson } from "../server/http";

function getR2Client(): S3Client | null {
  const accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
  const accessKeyId = process.env.R2_ACCESS_KEY_ID;
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY;
  if (!accountId || !accessKeyId || !secretAccessKey) return null;

  return new S3Client({
    region: "auto",
    endpoint: "https://" + accountId + ".r2.cloudflarestorage.com",
    credentials: { accessKeyId, secretAccessKey },
  });
}

export default async function handler(request: Request): Promise<Response> {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "POST") return json(request, { error: "Use POST." }, 405);

  try {
    const userId = guestIdFromRequest(request);
    await enforceRateLimit(userId, "image", 5, 60_000);
    const body = await readJson(request);
    const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
    if (!prompt) throw new HttpError(400, "Describe the image you want to generate.");
    if (prompt.length > 2048) throw new HttpError(413, "Image prompt must be no longer than 2,048 characters.");

    const accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
    const apiToken = process.env.CLOUDFLARE_API_TOKEN;
    if (!accountId || !apiToken) {
      throw new HttpError(503, "Backend setup is incomplete: Cloudflare Workers AI credentials are missing.");
    }

    const db = await getDb();
    const conversations = db.collection("conversations");
    const requestedConversationId =
      typeof body.conversationId === "string" ? body.conversationId : "";
    if (requestedConversationId && !/^[a-zA-Z0-9_-]{20,80}$/.test(requestedConversationId)) {
      throw new HttpError(400, "Invalid conversation ID.");
    }

    let conversationId = requestedConversationId;
    let conversation = conversationId
      ? await conversations.findOne({ _id: conversationId, userId })
      : null;

    if (conversationId && !conversation) {
      throw new HttpError(404, "Conversation not found. Start a new chat and try again.");
    }

    const now = new Date();
    if (!conversation) {
      conversationId = randomUUID();
      conversation = {
        _id: conversationId,
        userId,
        title: prompt.length > 80 ? prompt.slice(0, 77) + "..." : prompt,
        createdAt: now,
        updatedAt: now,
        lastMessage: prompt.slice(0, 240),
      };
      await conversations.insertOne(conversation);
    }

    const userMessageId = randomUUID();
    await db.collection("messages").insertOne({
      _id: userMessageId,
      userId,
      conversationId,
      role: "user",
      content: prompt,
      createdAt: now,
    });
    await conversations.updateOne(
      { _id: conversationId, userId },
      { $set: { updatedAt: now, lastMessage: prompt.slice(0, 240) } },
    );

    const model = "@cf/black-forest-labs/flux-1-schnell";
    const cfResponse = await fetch(
      "https://api.cloudflare.com/client/v4/accounts/" + accountId + "/ai/run/" + encodeURIComponent(model),
      {
        method: "POST",
        headers: {
          Authorization: "Bearer " + apiToken,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ prompt, steps: 4 }),
        signal: AbortSignal.timeout(55_000),
      },
    );

    if (!cfResponse.ok) {
      console.warn("[image] Cloudflare Workers AI request failed", cfResponse.status);
      throw new HttpError(502, "Image generation failed. Please try again in a moment.");
    }

    const payload = (await cfResponse.json()) as {
      success?: boolean;
      result?: { image?: string } | string;
      errors?: Array<{ message?: string }>;
    };
    const base64Image =
      typeof payload.result === "string"
        ? payload.result
        : typeof payload.result?.image === "string"
          ? payload.result.image
          : "";

    if (!payload.success || !base64Image) {
      throw new HttpError(502, "The image provider returned an empty result. Please try again.");
    }

    const bytes = Buffer.from(base64Image, "base64");
    if (bytes.length === 0 || bytes.length > 12 * 1024 * 1024) {
      throw new HttpError(502, "The image provider returned an invalid image.");
    }

    const assetId = randomUUID();
    const key = "generated/" + userId + "/" + assetId + ".jpg";
    let imageUrl: string | null = null;
    let dataUrl: string | null = "data:image/jpeg;base64," + bytes.toString("base64");
    let storedInR2 = false;

    const r2Client = getR2Client();
    const bucket = process.env.R2_BUCKET_NAME;
    if (r2Client && bucket) {
      try {
        await r2Client.send(
          new PutObjectCommand({
            Bucket: bucket,
            Key: key,
            Body: bytes,
            ContentType: "image/jpeg",
            CacheControl: "private, max-age=3600",
            Metadata: {
              "guest-id": userId.slice(0, 64),
              "prompt-hash": Buffer.from(prompt).toString("base64url").slice(0, 200),
            },
          }),
        );
        storedInR2 = true;
        dataUrl = null;
        const publicBase = process.env.R2_PUBLIC_BASE_URL?.replace(/\/+$/, "");
        imageUrl = publicBase
          ? publicBase + "/" + key.split("/").map(encodeURIComponent).join("/")
          : await getSignedUrl(
              r2Client,
              new GetObjectCommand({ Bucket: bucket, Key: key }),
              { expiresIn: 3600 },
            );
      } catch (error) {
        console.warn("[image] R2 storage failed; returning the image directly", error instanceof Error ? error.name : "UnknownError");
        imageUrl = null;
        dataUrl = "data:image/jpeg;base64," + bytes.toString("base64");
      }
    }

    await db.collection("assets").insertOne({
      _id: assetId,
      userId,
      type: "image",
      prompt,
      model,
      storage: storedInR2 ? "r2" : "inline",
      objectKey: storedInR2 ? key : null,
      imageUrl: storedInR2 ? imageUrl : null,
      createdAt: new Date(),
    });

    const assistantMessageId = randomUUID();
    await db.collection("messages").insertOne({
      _id: assistantMessageId,
      userId,
      conversationId,
      role: "assistant",
      content: "Generated an image for this prompt.",
      model,
      generatedImage: {
        assetId,
        imageUrl: storedInR2 ? imageUrl : null,
        storedInR2,
        prompt,
      },
      createdAt: new Date(),
    });
    await conversations.updateOne(
      { _id: conversationId, userId },
      { $set: { updatedAt: new Date(), lastMessage: "Generated image: " + prompt.slice(0, 180) } },
    );

    return json(request, {
      ok: true,
      assetId,
      conversationId,
      messageId: assistantMessageId,
      prompt,
      model,
      mimeType: "image/jpeg",
      dataUrl,
      imageUrl,
      storedInR2,
    });
  } catch (error) {
    return handleRouteError(request, error);
  }
}
