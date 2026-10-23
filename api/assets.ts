import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { guestIdFromRequest } from "../server/auth";
import { getDb } from "../server/db";
import { handleRouteError, HttpError, json, preflight } from "../server/http";
import { enforceRateLimit } from "../server/rate-limit";

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
  if (request.method !== "GET") return json(request, { error: "Use GET." }, 405);

  try {
    const userId = guestIdFromRequest(request);
    await enforceRateLimit(userId, "assets", 120, 60_000);
    const assetId = new URL(request.url).searchParams.get("id") || "";
    if (!/^[a-zA-Z0-9_-]{20,80}$/.test(assetId)) {
      throw new HttpError(400, "A valid asset ID is required.");
    }

    const db = await getDb();
    const asset = await db.collection<any>("assets").findOne({ _id: assetId, userId });
    if (!asset) return json(request, { error: "Image asset not found." }, 404);
    if (asset.storage !== "r2" || typeof asset.objectKey !== "string") {
      return json(
        request,
        { error: "This image was not saved to durable storage. Configure Cloudflare R2 to preserve generated images." },
        410,
      );
    }

    const r2 = getR2Client();
    const bucket = process.env.R2_BUCKET_NAME;
    if (!r2 || !bucket) {
      return json(request, { error: "R2 storage is not configured." }, 503);
    }

    const url = await getSignedUrl(
      r2,
      new GetObjectCommand({ Bucket: bucket, Key: asset.objectKey }),
      { expiresIn: 600 },
    );
    return json(request, {
      ok: true,
      assetId,
      url,
      mimeType: "image/jpeg",
      expiresIn: 600,
    });
  } catch (error) {
    return handleRouteError(request, error);
  }
}
