import 'package:supabase_flutter/supabase_flutter.dart';

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

class BuilderAssetRecord {
  const BuilderAssetRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.categorySlug,
    this.thumbnailUrl,
    this.modelUrl,
    this.role,
  });

  final String id;
  final String name;
  final String type;
  final String categorySlug;
  final String? thumbnailUrl;
  final String? modelUrl;
  final String? role;

  factory BuilderAssetRecord.fromJson(Map<String, dynamic> json) {
    return BuilderAssetRecord(
      id: json['id'] as String,
      name: (json['name'] ?? 'Asset') as String,
      type: (json['type'] ?? 'asset') as String,
      categorySlug: (json['category_slug'] ?? '') as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      modelUrl: (json['model_url'] ?? json['url']) as String?,
      role: json['role'] as String?,
    );
  }
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
            'id,name,type,category_slug,thumbnail_url,model_url,url,role',
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
}
