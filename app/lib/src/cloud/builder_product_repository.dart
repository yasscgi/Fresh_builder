import 'package:supabase_flutter/supabase_flutter.dart';

import 'builder_cloud_models.dart';
import 'supabase_bootstrap.dart';

final class BuilderProductSummary {
  const BuilderProductSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.imageUrl,
    required this.price,
    required this.clientOnly,
  });

  final String id;
  final String name;
  final String slug;
  final String? imageUrl;
  final int price;
  final bool clientOnly;

  factory BuilderProductSummary.fromRow(JsonMap row) {
    return BuilderProductSummary(
      id: row['id'].toString(),
      name: (row['name'] ?? 'Builder Product').toString(),
      slug: (row['slug'] ?? '').toString(),
      imageUrl: row['image_url']?.toString(),
      price: (row['price'] as num?)?.toInt() ?? 0,
      clientOnly: row['client_only'] == true,
    );
  }
}

final class BuilderProductRepository {
  BuilderProductRepository({SupabaseClient? client})
      : _client = client ?? FreshSupabaseBootstrap.requireClient();

  final SupabaseClient _client;

  Future<List<BuilderProductSummary>> listAccessibleBuilderProducts() async {
    final rows = await _client
        .from('products')
        .select('id,name,slug,image_url,price,client_only')
        .eq('builder_enabled', true)
        .eq('visible', true)
        .eq('status', 'published')
        .order('name');

    final products = jsonMapList(rows)
        .map(BuilderProductSummary.fromRow)
        .toList(growable: false);

    if (products.isEmpty) return const <BuilderProductSummary>[];

    final checks = await Future.wait(
      products.map((product) async {
        final result = await _client.rpc(
          'user_has_product_access',
          params: {'p_product_id': product.id},
        );
        return result == true;
      }),
    );

    final accessible = <BuilderProductSummary>[];
    for (var index = 0; index < products.length; index++) {
      if (checks[index]) accessible.add(products[index]);
    }
    return accessible;
  }
}
