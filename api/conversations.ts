import { guestIdFromRequest } from "../server/auth";
import { getDb } from "../server/db";
import { handleRouteError, json, preflight } from "../server/http";
import { enforceRateLimit } from "../server/rate-limit";

export default async function handler(request: Request): Promise<Response> {
  const options = preflight(request);
  if (options) return options;

  try {
    const userId = guestIdFromRequest(request);
    await enforceRateLimit(userId, "conversations", 90, 60_000);
    const db = await getDb();
    const conversationId = new URL(request.url).searchParams.get("id");

    if (request.method === "GET" && conversationId) {
      const conversation = await db.collection("conversations").findOne({
        _id: conversationId,
        userId,
      });
      if (!conversation) return json(request, { error: "Conversation not found." }, 404);

      const messages = await db.collection("messages")
        .find({ conversationId, userId })
        .sort({ createdAt: 1 })
        .limit(300)
        .toArray();

      return json(request, {
        conversation: {
          id: conversation._id,
          title: conversation.title,
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
        },
        messages: messages.map((message) => ({
          id: message._id,
          role: message.role,
          content: message.content,
          model: message.model || null,
          feedback: message.feedback || null,
          sources: message.sources || [],
          attachment: message.attachment || null,
          generatedImage: message.generatedImage || null,
          createdAt: message.createdAt,
        })),
      });
    }

    if (request.method === "GET") {
      const conversations = await db.collection("conversations")
        .find({ userId })
        .sort({ updatedAt: -1 })
        .limit(60)
        .toArray();

      return json(request, {
        conversations: conversations.map((conversation) => ({
          id: conversation._id,
          title: conversation.title,
          preview: conversation.lastMessage || "",
          createdAt: conversation.createdAt,
          updatedAt: conversation.updatedAt,
        })),
      });
    }

    return json(request, { error: "Use GET for conversation history." }, 405);
  } catch (error) {
    return handleRouteError(request, error);
  }
}
