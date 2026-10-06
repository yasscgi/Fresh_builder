import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2.95.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type AssetVariation = {
  id?: string;
  modelUrl?: string;
  model_url?: string;
  thumbnailUrl?: string;
  thumbnail_url?: string;
};

type StorageRef = {
  bucket: string | null;
  path: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "private, no-store",
    },
  });
}

function getRequestedUrl(
  asset: Record<string, unknown>,
  kind: "model" | "thumbnail",
  variationId: string | null,
): string {
  const metadata =
    asset.metadata && typeof asset.metadata === "object"
      ? (asset.metadata as Record<string, unknown>)
      : {};

  const variations = Array.isArray(asset.variations)
    ? (asset.variations as AssetVariation[])
    : Array.isArray(metadata.variations)
      ? (metadata.variations as AssetVariation[])
      : [];

  if (variationId) {
    const variation = variations.find((item) => item?.id === variationId);
    if (!variation) return "";
    return kind === "thumbnail"
      ? String(variation.thumbnailUrl ?? variation.thumbnail_url ?? "")
      : String(variation.modelUrl ?? variation.model_url ?? "");
  }

  if (kind === "thumbnail") {
    return String(
      asset.thumbnail_url ??
        metadata.thumbnailUrl ??
        metadata.previewImageUrl ??
        "",
    );
  }

  return String(
    asset.model_url ??
      asset.url ??
      metadata.modelUrl ??
      metadata.fileUrl ??
      "",
  );
}

function parseStorageRef(value: string): StorageRef {
  const trimmed = String(value || "").trim();
  if (!trimmed) return { bucket: null, path: "" };

  if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) {
    const normalized = trimmed.replace(/^\/+/, "").replace(/^public\//, "");
    if (normalized.startsWith("private-downloads/")) {
      return {
        bucket: "private-downloads",
        path: normalized.replace(/^private-downloads\//, ""),
      };
    }
    if (normalized.startsWith("protected/")) {
      return { bucket: "private-downloads", path: normalized };
    }
    if (/^products\/[^/]+\/(?:source|builder)\//.test(normalized)) {
      return { bucket: "private-downloads", path: normalized };
    }
    if (normalized.startsWith("products/") || normalized.startsWith("images/")) {
      return { bucket: "public", path: normalized };
    }
    return { bucket: "public", path: normalized };
  }

  try {
    const url = new URL(trimmed);
    const pathname = decodeURIComponent(url.pathname);
    const match = pathname.match(
      /\/storage\/v1\/object\/(sign|public|authenticated)\/([^/]+)\/(.+)$/,
    );
    if (!match) return { bucket: null, path: trimmed };

    const accessMode = match[1];
    const firstSegment = match[2];
    const path = match[3];

    if (firstSegment === "private-downloads") {
      return { bucket: "private-downloads", path };
    }
    if (firstSegment === "public") {
      return { bucket: "public", path };
    }
    if (accessMode === "authenticated" && firstSegment === "protected") {
      return { bucket: "private-downloads", path: `protected/${path}` };
    }
    if (accessMode === "public") {
      return { bucket: "public", path: `${firstSegment}/${path}` };
    }
    if (accessMode === "sign") {
      return { bucket: firstSegment, path };
    }

    return { bucket: null, path: trimmed };
  } catch {
    return { bucket: null, path: trimmed };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ error: "Authentication required" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const publishableKeys = JSON.parse(
    Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}",
  ) as Record<string, string>;
  const clientKey =
    publishableKeys.default ?? Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!supabaseUrl || !clientKey || !serviceRoleKey) {
    return json({ error: "Supabase function environment is incomplete" }, 500);
  }

  const token = authHeader.slice("Bearer ".length).trim();

  const userClient = createClient(supabaseUrl, clientKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser(token);

  if (userError || !user) {
    return json({ error: "Invalid or expired session" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const assetId = String(body.asset_id ?? "").trim();
  const kind = body.kind === "thumbnail" ? "thumbnail" : "model";
  const variationId = body.variation_id
    ? String(body.variation_id).trim()
    : null;

  if (!assetId) {
    return json({ error: "asset_id is required" }, 400);
  }

  const { data: asset, error: assetError } = await userClient
    .from("builder_assets")
    .select(
      "id,product_id,model_url,url,thumbnail_url,metadata,variations,updated_at",
    )
    .eq("id", assetId)
    .maybeSingle();

  if (assetError) {
    console.error("builder-asset-url asset query failed", {
      assetId,
      code: assetError.code,
    });
    return json({ error: "Unable to verify Builder asset access" }, 500);
  }

  if (!asset) {
    return json({ error: "Builder asset unavailable" }, 403);
  }

  const storedUrl = getRequestedUrl(asset, kind, variationId);
  if (!storedUrl) {
    return json({ error: "Requested Builder file was not found" }, 404);
  }

  const ref = parseStorageRef(storedUrl);
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (ref.bucket === "private-downloads") {
    const { data: signed, error: signedError } = await admin.storage
      .from("private-downloads")
      .createSignedUrl(ref.path, 10 * 60);

    if (signedError || !signed?.signedUrl) {
      console.error("builder-asset-url signing failed", {
        assetId,
        productId: asset.product_id,
        kind,
        variationId,
        path: ref.path,
        message: signedError?.message ?? "missing signedUrl",
      });
      return json({ error: "Unable to create Builder asset URL" }, 500);
    }

    return json({
      url: signed.signedUrl,
      expires_in: 600,
      asset_id: assetId,
      kind,
      variation_id: variationId,
      version: asset.updated_at ?? null,
    });
  }

  if (ref.bucket === "public") {
    const { data } = admin.storage.from("public").getPublicUrl(ref.path);
    return json({
      url: data.publicUrl,
      expires_in: null,
      asset_id: assetId,
      kind,
      variation_id: variationId,
      version: asset.updated_at ?? null,
    });
  }

  if (storedUrl.startsWith("https://")) {
    return json({
      url: storedUrl,
      expires_in: null,
      asset_id: assetId,
      kind,
      variation_id: variationId,
      version: asset.updated_at ?? null,
    });
  }

  return json({ error: "Unsupported Builder storage reference" }, 400);
});
