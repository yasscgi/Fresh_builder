import 'package:supabase_flutter/supabase_flutter.dart';

import 'builder_cloud_models.dart';
import 'supabase_bootstrap.dart';

final class SavedBuilderDesign {
  const SavedBuilderDesign({
    required this.id,
    required this.productId,
    required this.name,
    required this.design,
    required this.thumbnailUrl,
    required this.exportUrl,
    required this.updatedAt,
  });

  final String id;
  final String? productId;
  final String name;
  final JsonMap design;
  final String? thumbnailUrl;
  final String? exportUrl;
  final DateTime? updatedAt;

  factory SavedBuilderDesign.fromRow(JsonMap row) {
    return SavedBuilderDesign(
      id: row['id'].toString(),
      productId: row['product_id']?.toString(),
      name: (row['name'] ?? 'My Design').toString(),
      design: jsonMap(row['design']),
      thumbnailUrl: row['thumbnail_url']?.toString(),
      exportUrl: row['export_url']?.toString(),
      updatedAt: DateTime.tryParse((row['updated_at'] ?? '').toString()),
    );
  }
}

final class SavedDesignRepository {
  SavedDesignRepository({SupabaseClient? client})
      : _client = client ?? FreshSupabaseBootstrap.requireClient();

  final SupabaseClient _client;

  User _requireUser() {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before working with saved designs.');
    }
    return user;
  }

  Future<String> save({
    required String productId,
    required JsonMap design,
    String name = 'My Design',
  }) async {
    final user = _requireUser();
    final trimmed = name.trim();
    final safeName = trimmed.isEmpty
        ? 'My Design'
        : trimmed.length > 80
            ? trimmed.substring(0, 80)
            : trimmed;

    final row = await _client
        .from('saved_builder_designs')
        .insert({
          'user_id': user.id,
          'product_id': productId,
          'name': safeName,
          'design': design,
        })
        .select('id')
        .single();

    return row['id'].toString();
  }

  Future<List<SavedBuilderDesign>> listForProduct(
    String productId,
  ) async {
    final user = _requireUser();
    final rows = await _client
        .from('saved_builder_designs')
        .select()
        .eq('user_id', user.id)
        .eq('product_id', productId)
        .order('updated_at', ascending: false);

    return jsonMapList(rows)
        .map(SavedBuilderDesign.fromRow)
        .toList(growable: false);
  }

  Future<SavedBuilderDesign?> getById({
    required String productId,
    required String designId,
  }) async {
    final user = _requireUser();
    final row = await _client
        .from('saved_builder_designs')
        .select()
        .eq('id', designId)
        .eq('product_id', productId)
        .eq('user_id', user.id)
        .maybeSingle();

    return row == null
        ? null
        : SavedBuilderDesign.fromRow(jsonMap(row));
  }

  Future<void> delete(String designId) async {
    final user = _requireUser();
    await _client
        .from('saved_builder_designs')
        .delete()
        .eq('id', designId)
        .eq('user_id', user.id);
  }
}
