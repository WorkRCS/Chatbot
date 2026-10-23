import { guestIdFromRequest } from "../server/auth";
import { getDb } from "../server/db";
import { handleRouteError, HttpError, json, preflight, readJson } from "../server/http";
import { enforceRateLimit } from "../server/rate-limit";

export default async function handler(request: Request): Promise<Response> {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "POST") return json(request, { error: "Use POST." }, 405);

  try {
    const userId = guestIdFromRequest(request);
    await enforceRateLimit(userId, "feedback", 60, 60_000);
    const body = await readJson(request);
    const messageId = typeof body.messageId === "string" ? body.messageId : "";
    const reaction = body.reaction;

    if (!/^[a-zA-Z0-9_-]{20,80}$/.test(messageId)) {
      throw new HttpError(400, "A valid messageId is required.");
    }
    if (reaction !== "like" && reaction !== "dislike" && reaction !== null) {
      throw new HttpError(400, "Reaction must be like, dislike, or null.");
    }

    const db = await getDb();
    const message = await db.collection("messages").findOne({
      _id: messageId,
      userId,
      role: "assistant",
    });
    if (!message) return json(request, { error: "Assistant message not found." }, 404);

    await db.collection("messages").updateOne(
      { _id: messageId, userId },
      { $set: { feedback: reaction, feedbackUpdatedAt: new Date() } },
    );

    await db.collection("feedback").updateOne(
      { userId, messageId },
      {
        $set: { reaction, updatedAt: new Date(), conversationId: message.conversationId },
        $setOnInsert: { createdAt: new Date() },
      },
      { upsert: true },
    );

    return json(request, { ok: true, messageId, reaction });
  } catch (error) {
    return handleRouteError(request, error);
  }
}
