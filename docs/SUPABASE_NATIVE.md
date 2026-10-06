# Supabase Native Cloud

Fresh Builder Native uses the existing FreshSTL Supabase project and the same product-access rules as the web Builder.

## Security model

The desktop/mobile app is a public client. It must only contain the Supabase **publishable key**.

Never place a secret key, service-role key, or database password in Flutter, Rust, GitHub source, release artifacts, or `--dart-define`.

Database reads use the signed-in user's Supabase session, so existing Row Level Security policies remain authoritative.

### Protected Builder assets

The `private-downloads` bucket is intentionally not opened to native clients.

Fresh Builder invokes the authenticated Edge Function:

`builder-asset-url`

The function:

1. requires a valid user JWT,
2. queries `builder_assets` in the user's auth context,
3. lets existing RLS / `user_has_product_access(product_id)` decide access,
4. uses the server-only storage credential to mint a short-lived signed URL,
5. returns that URL to the app.

Signed URLs are cached in memory by the Flutter client until shortly before expiration. Model bytes are then stored in a versioned application-support disk cache, so selecting the same unchanged asset does not download it again.

## Client configuration

The project URL defaults to the FreshSTL project URL. Supply the publishable key at build/run time:

```bash
flutter run \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
```

Optional custom project URL:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://project-ref.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
```

If no publishable key is supplied the app starts in **Local Mode** and cloud controls are disabled.

## Native cloud flow

```text
Flutter
  -> Supabase Auth
  -> products (published/visible Builder products)
  -> user_has_product_access(product_id)
  -> builder_configs / builder_categories / builder_assets
  -> saved_builder_designs

Protected model/thumbnail:
Flutter
  -> builder-asset-url Edge Function
  -> user-scoped builder_assets query (RLS)
  -> 10-minute signed Storage URL
  -> in-memory URL cache
```

## Existing FreshSTL data reused

The native app reads the current production tables rather than creating a parallel backend:

- `products`
- `builder_configs`
- `builder_categories`
- `builder_assets`
- `builder_articulated_chains`
- `builder_joint_standards`
- `builder_surface_zones`
- `saved_builder_designs`

## Current UI integration

The native shell now supports:

- account sign in / account creation / sign out,
- accessible Builder product picker,
- loading real Builder configuration and assets,
- dynamic category navigation,
- protected thumbnail resolution,
- cloud asset dock with selectable variations,
- secure native model download/cache pipeline,
- RLS-backed saved-design repository,
- Rust `builder_io` format detection for cached local files.

The next rendering integration is to pass the cached local model path through the existing Flutter/Rust bridge into the Rust/WGPU importer. Network authorization and downloading now stay outside the renderer.
