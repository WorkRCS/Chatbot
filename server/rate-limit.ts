import { getDb } from "./db";
import { HttpError } from "./http";

export async function enforceRateLimit(
  guestId: string,
  route: string,
  limit = 20,
  windowMs = 60_000,
): Promise<void> {
  const db = await getDb();
  const now = Date.now();
  const windowStart = Math.floor(now / windowMs) * windowMs;
  const id = route + ":" + guestId;
  const result = await db.collection<any>("rate_limits").findOneAndUpdate(
    { _id: id },
    [
      {
        $set: {
          windowStart: {
            $cond: [
              { $eq: ["$windowStart", windowStart] },
              "$windowStart",
              windowStart,
            ],
          },
          count: {
            $cond: [
              { $eq: ["$windowStart", windowStart] },
              { $add: [{ $ifNull: ["$count", 0] }, 1] },
              1,
            ],
          },
          expiresAt: new Date(windowStart + windowMs * 2),
        },
      },
    ],
    { upsert: true, returnDocument: "after" },
  );

  if ((result?.count ?? 0) > limit) {
    throw new HttpError(429, "Too many requests. Please wait a moment and try again.");
  }
}
