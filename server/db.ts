import { MongoClient, type Db } from "mongodb";

declare global {
  // Reuse one Mongo client across warm Vercel function invocations.
  // eslint-disable-next-line no-var
  var __aiChatMongoClientPromise: Promise<MongoClient> | undefined;
}

export async function getDb(): Promise<Db> {
  const uri = process.env.MONGODB_URI;
  if (!uri) throw new Error("MONGODB_URI is not configured");

  if (!global.__aiChatMongoClientPromise) {
    const client = new MongoClient(uri, {
      maxPoolSize: 5,
      minPoolSize: 0,
      serverSelectionTimeoutMS: 8000,
      connectTimeoutMS: 8000,
    });
    global.__aiChatMongoClientPromise = client.connect();
  }

  const client = await global.__aiChatMongoClientPromise;
  return client.db(process.env.MONGODB_DB_NAME || "ai_chat");
}

export async function ensureIndexes(): Promise<void> {
  const db = await getDb();
  await Promise.all([
    db.collection("conversations").createIndex({ userId: 1, updatedAt: -1 }),
    db.collection("messages").createIndex({ userId: 1, conversationId: 1, createdAt: 1 }),
    db.collection("feedback").createIndex({ userId: 1, messageId: 1 }, { unique: true }),
    db.collection("assets").createIndex({ userId: 1, createdAt: -1 }),
    db.collection("rate_limits").createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 }),
  ]);
}
