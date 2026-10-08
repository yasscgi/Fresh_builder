import 'package:supabase_flutter/supabase_flutter.dart';

final class BuilderDesignCloudRepository {
  BuilderDesignCloudRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  bool get signedIn => currentUserId != null;

  Future<String?> saveDesign({
    required String productId,
    required String name,
    required Map<String, dynamic> design,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;

    final safeName = name.trim().isEmpty
        ? 'My Design'
        : name.trim().substring(
            0,
            name.trim().length.clamp(0, 80).toInt(),
          );

    final row = await _client
        .from('saved_builder_designs')
        .insert({
          'user_id': userId,
          'product_id': productId,
          'name': safeName,
          'design': design,
        })
        .select('id')
        .single();

    return row['id']?.toString();
  }

  Future<BuilderCloudSavedDesign?> latestDesign({
    required String productId,
  }) async {
    final userId = currentUserId;
    if (userId == null) return null;

    final rows = await _client
        .from('saved_builder_designs')
        .select('id,name,product_id,design,created_at,updated_at')
        .eq('user_id', userId)
        .eq('product_id', productId)
        .order('updated_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return BuilderCloudSavedDesign.fromJson(
      Map<String, dynamic>.from(rows.first),
    );
  }

  Future<List<BuilderCloudSavedDesign>> listDesigns({
    required String productId,
    int limit = 20,
  }) async {
    final userId = currentUserId;
    if (userId == null) return const [];

    final rows = await _client
        .from('saved_builder_designs')
        .select('id,name,product_id,design,created_at,updated_at')
        .eq('user_id', userId)
        .eq('product_id', productId)
        .order('updated_at', ascending: false)
        .limit(limit.clamp(1, 100).toInt());

    return [
      for (final raw in rows)
        BuilderCloudSavedDesign.fromJson(
          Map<String, dynamic>.from(raw),
        ),
    ];
  }

  Future<void> deleteDesign(String designId) async {
    final userId = currentUserId;
    if (userId == null) return;

    await _client
        .from('saved_builder_designs')
        .delete()
        .eq('id', designId)
        .eq('user_id', userId);
  }
}

final class BuilderCloudSavedDesign {
  const BuilderCloudSavedDesign({
    required this.id,
    required this.name,
    required this.productId,
    required this.design,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? productId;
  final Map<String, dynamic> design;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory BuilderCloudSavedDesign.fromJson(Map<String, dynamic> json) {
    final rawDesign = json['design'];
    return BuilderCloudSavedDesign(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'My Design',
      productId: json['product_id']?.toString(),
      design: rawDesign is Map
          ? rawDesign.map(
              (key, value) => MapEntry(key.toString(), value),
            )
          : <String, dynamic>{},
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}
