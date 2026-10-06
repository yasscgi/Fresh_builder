import 'package:supabase_flutter/supabase_flutter.dart';

import 'builder_cloud_models.dart';
import 'supabase_bootstrap.dart';

final class BuilderCloudRepository {
  BuilderCloudRepository({SupabaseClient? client})
      : _client = client ?? FreshSupabaseBootstrap.requireClient();

  final SupabaseClient _client;

  Future<BuilderCloudData> loadBuilderData(String productId) async {
    final results = await Future.wait<Object?>([
      _loadConfig(productId),
      _loadCategories(productId),
      _loadAssets(productId),
      _loadRows(
        table: 'builder_articulated_chains',
        productId: productId,
        orderBy: 'sort_order',
      ),
      _loadRows(
        table: 'builder_joint_standards',
        productId: productId,
        orderBy: 'created_at',
      ),
      _loadRows(
        table: 'builder_surface_zones',
        productId: productId,
        orderBy: 'sort_order',
      ),
    ]);

    return BuilderCloudData(
      config: results[0] as BuilderCloudConfig?,
      categories: results[1] as List<BuilderCloudCategory>,
      assets: results[2] as List<BuilderCloudAsset>,
      articulatedChains: results[3] as List<JsonMap>,
      jointStandards: results[4] as List<JsonMap>,
      surfaceZones: results[5] as List<JsonMap>,
    );
  }

  Future<bool> hasProductAccess(String productId) async {
    final result = await _client.rpc(
      'user_has_product_access',
      params: {'p_product_id': productId},
    );
    return result == true;
  }

  Future<BuilderCloudConfig?> _loadConfig(String productId) async {
    final row = await _client
        .from('builder_configs')
        .select('product_id,config,builder_mode')
        .eq('product_id', productId)
        .maybeSingle();

    return row == null ? null : BuilderCloudConfig.fromRow(jsonMap(row));
  }

  Future<List<BuilderCloudCategory>> _loadCategories(
    String productId,
  ) async {
    final rows = await _client
        .from('builder_categories')
        .select(
          'id,product_id,name,slug,type,slot,required,allow_none,selection_mode,sort_order,customer_controls,ui_config',
        )
        .eq('product_id', productId)
        .order('sort_order');

    return jsonMapList(rows)
        .map(BuilderCloudCategory.fromRow)
        .toList(growable: false);
  }

  Future<List<BuilderCloudAsset>> _loadAssets(String productId) async {
    final rows = await _client
        .from('builder_assets')
        .select(
          'id,product_id,name,type,category_id,category_slug,model_url,url,thumbnail_url,role,metadata,variations,created_at,updated_at',
        )
        .eq('product_id', productId)
        .order('created_at');

    return jsonMapList(rows)
        .where(
          (row) =>
              row['type'] != 'category' &&
              row['type'] != 'builder-category',
        )
        .map(BuilderCloudAsset.fromRow)
        .toList(growable: false);
  }

  Future<List<JsonMap>> _loadRows({
    required String table,
    required String productId,
    required String orderBy,
  }) async {
    final rows = await _client
        .from(table)
        .select()
        .eq('product_id', productId)
        .order(orderBy);

    return jsonMapList(rows);
  }
}
