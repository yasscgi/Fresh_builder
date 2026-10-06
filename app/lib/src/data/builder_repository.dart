import 'package:supabase_flutter/supabase_flutter.dart';

const _privateDownloadsBucket = 'private-downloads';

class BuilderCategoryRecord {
  const BuilderCategoryRecord({
    required this.id,
    required this.name,
    required this.slug,
    required this.type,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String slug;
  final String type;
  final int sortOrder;

  factory BuilderCategoryRecord.fromJson(Map<String, dynamic> json) {
    return BuilderCategoryRecord(
      id: json['id'] as String,
      name: (json['name'] ?? json['slug'] ?? 'Asset') as String,
      slug: (json['slug'] ?? '') as String,
      type: (json['type'] ?? 'asset') as String,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class BuilderAssetVariationRecord {
  const BuilderAssetVariationRecord({
    required this.id,
    required this.name,
    required this.metadata,
    this.modelPath,
    this.thumbnailPath,
  });

  final String id;
  final String name;
  final Map<String, dynamic> metadata;
  final String? modelPath;
  final String? thumbnailPath;

  String? get sourceFormat =>
      (metadata['sourceFormat'] as String?)?.toLowerCase();

  double get metersPerBlenderUnit =>
      (metadata['metersPerBlenderUnit'] as num?)?.toDouble() ?? 1.0;

  factory BuilderAssetVariationRecord.fromJson(Map<String, dynamic> json) {
    return BuilderAssetVariationRecord(
      id: json['id'] as String,
      name: (json['name'] ?? 'Variation') as String,
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map?) ?? const <String, dynamic>{},
      ),
      modelPath: json['modelUrl'] as String?,
      thumbnailPath: json['thumbnailUrl'] as String?,
    );
  }
}

class BuilderAssetRecord {
  const BuilderAssetRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.categorySlug,
    required this.metadata,
    required this.variations,
    this.thumbnailPath,
    this.modelPath,
    this.role,
  });

  final String id;
  final String name;
  final String type;
  final String categorySlug;
  final String? thumbnailPath;
  final String? modelPath;
  final String? role;
  final Map<String, dynamic> metadata;
  final List<BuilderAssetVariationRecord> variations;

  bool get isPose => type == 'pose';
  bool get isRig => type == 'rig' || role == 'rig';
  bool get isBaseCharacter =>
      type == 'base_character' || role == 'base_character';

  factory BuilderAssetRecord.fromJson(Map<String, dynamic> json) {
    final variationRows = (json['variations'] as List?) ?? const [];
    return BuilderAssetRecord(
      id: json['id'] as String,
      name: (json['name'] ?? 'Asset') as String,
      type: (json['type'] ?? 'asset') as String,
      categorySlug: (json['category_slug'] ?? '') as String,
      thumbnailPath: json['thumbnail_url'] as String?,
      modelPath: (json['model_url'] ?? json['url']) as String?,
      role: json['role'] as String?,
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map?) ?? const <String, dynamic>{},
      ),
      variations: variationRows
          .map((row) => BuilderAssetVariationRecord.fromJson(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(growable: false),
    );
  }
}

class ResolvedBuilderAsset {
  const ResolvedBuilderAsset({
    required this.assetId,
    required this.name,
    required this.type,
    required this.role,
    required this.variationId,
    required this.sourceFormat,
    required this.metersPerBlenderUnit,
    required this.modelUrl,
    this.thumbnailUrl,
  });

  final String assetId;
  final String name;
  final String type;
  final String? role;
  final String? variationId;
  final String sourceFormat;
  final double metersPerBlenderUnit;
  final String modelUrl;
  final String? thumbnailUrl;

  String get cacheKey => variationId == null
      ? assetId
      : '$assetId:$variationId';
}

class BuilderProductBundle {
  const BuilderProductBundle({
    required this.productId,
    required this.mode,
    required this.config,
    required this.categories,
    required this.assets,
  });

  final String productId;
  final String mode;
  final Map<String, dynamic> config;
  final List<BuilderCategoryRecord> categories;
  final List<BuilderAssetRecord> assets;
}

class BuilderRepository {
  BuilderRepository(this._client);

  final SupabaseClient _client;

  Future<List<String>> listBuilderProductIds() async {
    final rows = await _client
        .from('products')
        .select('id')
        .eq('builder_enabled', true)
        .limit(50);

    return (rows as List<dynamic>)
        .map((row) => (row as Map<String, dynamic>)['id'] as String)
        .toList(growable: false);
  }

  Future<BuilderProductBundle> loadProduct(String productId) async {
    final results = await Future.wait<dynamic>([
      _client
          .from('builder_configs')
          .select('product_id,builder_mode,config')
          .eq('product_id', productId)
          .maybeSingle(),
      _client
          .from('builder_categories')
          .select('id,name,slug,type,sort_order')
          .eq('product_id', productId)
          .order('sort_order'),
      _client
          .from('builder_assets')
          .select(
            'id,name,type,category_slug,thumbnail_url,model_url,url,role,metadata,variations',
          )
          .eq('product_id', productId)
          .order('created_at'),
    ]);

    final configRow = results[0] as Map<String, dynamic>?;
    final categoryRows = results[1] as List<dynamic>;
    final assetRows = results[2] as List<dynamic>;

    return BuilderProductBundle(
      productId: productId,
      mode: (configRow?['builder_mode'] ?? 'character') as String,
      config: Map<String, dynamic>.from(
        (configRow?['config'] as Map?) ?? const <String, dynamic>{},
      ),
      categories: categoryRows
          .map((row) => BuilderCategoryRecord.fromJson(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(growable: false),
      assets: assetRows
          .map((row) => BuilderAssetRecord.fromJson(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList(growable: false),
    );
  }

  Future<ResolvedBuilderAsset> resolveAsset(
    BuilderAssetRecord asset, {
    String? variationId,
    int expiresInSeconds = 900,
  }) async {
    final variation = _selectVariation(asset, variationId);
    final modelPath = variation?.modelPath ?? asset.modelPath;

    if (modelPath == null || modelPath.isEmpty) {
      throw StateError('Asset ${asset.id} does not contain a model path.');
    }

    final thumbnailPath = variation?.thumbnailPath ?? asset.thumbnailPath;
    final modelUrl = await _resolveStorageUrl(
      modelPath,
      expiresInSeconds: expiresInSeconds,
    );
    final thumbnailUrl = thumbnailPath == null
        ? null
        : await _resolveStorageUrl(
            thumbnailPath,
            expiresInSeconds: expiresInSeconds,
          );

    final sourceFormat = variation?.sourceFormat ??
        _sourceFormatFromPath(modelPath) ??
        ((asset.metadata['sourceFormat'] as String?)?.toLowerCase()) ??
        'unknown';

    return ResolvedBuilderAsset(
      assetId: asset.id,
      name: variation?.name ?? asset.name,
      type: asset.type,
      role: asset.role,
      variationId: variation?.id,
      sourceFormat: sourceFormat,
      metersPerBlenderUnit: variation?.metersPerBlenderUnit ??
          (asset.metadata['metersPerBlenderUnit'] as num?)?.toDouble() ??
          1.0,
      modelUrl: modelUrl,
      thumbnailUrl: thumbnailUrl,
    );
  }

  BuilderAssetVariationRecord? _selectVariation(
    BuilderAssetRecord asset,
    String? variationId,
  ) {
    if (asset.variations.isEmpty) return null;
    if (variationId == null) return asset.variations.first;

    for (final variation in asset.variations) {
      if (variation.id == variationId) return variation;
    }

    throw StateError(
      'Variation $variationId does not belong to asset ${asset.id}.',
    );
  }

  Future<String> _resolveStorageUrl(
    String path, {
    required int expiresInSeconds,
  }) async {
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) return path;

    final normalized = path.startsWith('$_privateDownloadsBucket/')
        ? path.substring(_privateDownloadsBucket.length + 1)
        : path;

    return _client.storage
        .from(_privateDownloadsBucket)
        .createSignedUrl(normalized, expiresInSeconds);
  }

  String? _sourceFormatFromPath(String path) {
    final clean = path.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return null;
    return clean.substring(dot + 1).toLowerCase();
  }
}
