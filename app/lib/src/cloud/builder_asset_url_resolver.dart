import 'package:supabase_flutter/supabase_flutter.dart';

import 'builder_cloud_models.dart';
import 'supabase_bootstrap.dart';

final class BuilderAssetUrl {
  const BuilderAssetUrl({
    required this.uri,
    required this.expiresAt,
    required this.version,
  });

  final Uri uri;
  final DateTime? expiresAt;
  final String? version;

  bool get isFresh {
    final expiry = expiresAt;
    if (expiry == null) return true;
    return DateTime.now().isBefore(expiry);
  }
}

final class BuilderAssetUrlResolver {
  BuilderAssetUrlResolver({SupabaseClient? client})
      : _client = client ?? FreshSupabaseBootstrap.requireClient();

  final SupabaseClient _client;
  final Map<String, BuilderAssetUrl> _cache = {};

  Future<BuilderAssetUrl> resolve({
    required String assetId,
    String kind = 'model',
    String? variationId,
    bool forceRefresh = false,
  }) async {
    final normalizedKind = kind == 'thumbnail' ? 'thumbnail' : 'model';
    final cacheKey =
        '$assetId|$normalizedKind|${variationId ?? '-'}';

    if (!forceRefresh) {
      final cached = _cache[cacheKey];
      if (cached != null && cached.isFresh) return cached;
    }

    if (_client.auth.currentSession == null) {
      throw StateError('Sign in before requesting protected Builder files.');
    }

    final response = await _client.functions.invoke(
      'builder-asset-url',
      body: <String, dynamic>{
        'asset_id': assetId,
        'kind': normalizedKind,
        if (variationId != null) 'variation_id': variationId,
      },
    );

    final data = jsonMap(response.data);
    final rawUrl = (data['url'] ?? '').toString();
    if (rawUrl.isEmpty) {
      throw StateError(
        (data['error'] ?? 'Builder asset URL was not returned.').toString(),
      );
    }

    final expiresIn = (data['expires_in'] as num?)?.toInt();
    final cacheSeconds = expiresIn == null
        ? null
        : expiresIn > 90
            ? expiresIn - 60
            : expiresIn;

    final result = BuilderAssetUrl(
      uri: Uri.parse(rawUrl),
      expiresAt: cacheSeconds == null
          ? null
          : DateTime.now().add(Duration(seconds: cacheSeconds)),
      version: data['version']?.toString(),
    );

    _cache[cacheKey] = result;
    return result;
  }

  void invalidateAsset(String assetId) {
    _cache.removeWhere((key, _) => key.startsWith('$assetId|'));
  }

  void clear() => _cache.clear();
}
