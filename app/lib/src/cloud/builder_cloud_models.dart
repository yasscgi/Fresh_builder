typedef JsonMap = Map<String, dynamic>;

JsonMap jsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}

List<JsonMap> jsonMapList(Object? value) {
  if (value is! List) return const <JsonMap>[];
  return value.map(jsonMap).toList(growable: false);
}

final class BuilderCloudConfig {
  const BuilderCloudConfig({
    required this.productId,
    required this.mode,
    required this.config,
  });

  final String productId;
  final String mode;
  final JsonMap config;

  factory BuilderCloudConfig.fromRow(JsonMap row) {
    final rawMode = (row['builder_mode'] ?? 'character').toString();
    final mode =
        rawMode == 'articulated' || rawMode == 'surface_svg'
            ? rawMode
            : 'character';

    return BuilderCloudConfig(
      productId: row['product_id'].toString(),
      mode: mode,
      config: jsonMap(row['config']),
    );
  }
}

final class BuilderCloudCategory {
  const BuilderCloudCategory({
    required this.id,
    required this.productId,
    required this.name,
    required this.slug,
    required this.type,
    required this.sortOrder,
    required this.required,
    required this.allowNone,
    required this.selectionMode,
    required this.slot,
    required this.customerControls,
    required this.uiConfig,
  });

  final String id;
  final String productId;
  final String name;
  final String slug;
  final String type;
  final int sortOrder;
  final bool required;
  final bool allowNone;
  final String selectionMode;
  final String? slot;
  final JsonMap customerControls;
  final JsonMap uiConfig;

  factory BuilderCloudCategory.fromRow(JsonMap row) {
    return BuilderCloudCategory(
      id: row['id'].toString(),
      productId: row['product_id'].toString(),
      name: (row['name'] ?? '').toString(),
      slug: (row['slug'] ?? '').toString(),
      type: (row['type'] ?? 'attachment').toString(),
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      required: row['required'] == true,
      allowNone: row['allow_none'] != false,
      selectionMode: (row['selection_mode'] ?? 'single').toString(),
      slot: row['slot']?.toString(),
      customerControls: jsonMap(row['customer_controls']),
      uiConfig: jsonMap(row['ui_config']),
    );
  }
}

final class BuilderCloudVariation {
  const BuilderCloudVariation({
    required this.id,
    required this.name,
    required this.modelRef,
    required this.thumbnailRef,
    required this.metadata,
  });

  final String id;
  final String name;
  final String? modelRef;
  final String? thumbnailRef;
  final JsonMap metadata;

  factory BuilderCloudVariation.fromJson(JsonMap row) {
    return BuilderCloudVariation(
      id: (row['id'] ?? '').toString(),
      name: (row['name'] ?? 'Variation').toString(),
      modelRef: (row['modelUrl'] ?? row['model_url'])?.toString(),
      thumbnailRef:
          (row['thumbnailUrl'] ?? row['thumbnail_url'])?.toString(),
      metadata: jsonMap(row['metadata']),
    );
  }
}

final class BuilderCloudAsset {
  const BuilderCloudAsset({
    required this.id,
    required this.productId,
    required this.name,
    required this.type,
    required this.categoryId,
    required this.categorySlug,
    required this.modelRef,
    required this.thumbnailRef,
    required this.role,
    required this.metadata,
    required this.variations,
    required this.updatedAt,
  });

  final String id;
  final String productId;
  final String name;
  final String? type;
  final String? categoryId;
  final String? categorySlug;
  final String? modelRef;
  final String? thumbnailRef;
  final String role;
  final JsonMap metadata;
  final List<BuilderCloudVariation> variations;
  final String? updatedAt;

  factory BuilderCloudAsset.fromRow(JsonMap row) {
    final metadata = jsonMap(row['metadata']);
    final role =
        (row['role'] ?? metadata['role'] ?? 'regular').toString();

    return BuilderCloudAsset(
      id: row['id'].toString(),
      productId: (row['product_id'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      type: row['type']?.toString(),
      categoryId: row['category_id']?.toString(),
      categorySlug: row['category_slug']?.toString(),
      modelRef: (row['model_url'] ?? row['url'])?.toString(),
      thumbnailRef: row['thumbnail_url']?.toString(),
      role: role,
      metadata: metadata,
      variations: jsonMapList(row['variations'])
          .map(BuilderCloudVariation.fromJson)
          .toList(growable: false),
      updatedAt: row['updated_at']?.toString(),
    );
  }
}

final class BuilderAssetChoice {
  const BuilderAssetChoice({
    required this.asset,
    this.variation,
  });

  final BuilderCloudAsset asset;
  final BuilderCloudVariation? variation;

  String get assetId => asset.id;
  String? get variationId => variation?.id;
  String get name => variation?.name ?? asset.name;
  String get selectionKey =>
      variationId == null ? asset.id : '${asset.id}|$variationId';

  JsonMap get metadata =>
      variation?.metadata.isNotEmpty == true ? variation!.metadata : asset.metadata;
}

final class BuilderCloudData {
  const BuilderCloudData({
    required this.config,
    required this.categories,
    required this.assets,
    required this.articulatedChains,
    required this.jointStandards,
    required this.surfaceZones,
  });

  final BuilderCloudConfig? config;
  final List<BuilderCloudCategory> categories;
  final List<BuilderCloudAsset> assets;
  final List<JsonMap> articulatedChains;
  final List<JsonMap> jointStandards;
  final List<JsonMap> surfaceZones;
}
