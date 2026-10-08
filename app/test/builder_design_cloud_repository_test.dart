import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_builder/src/cloud/builder_design_cloud_repository.dart';

void main() {
  test('parses Supabase saved_builder_designs row', () {
    final design = BuilderCloudSavedDesign.fromJson({
      'id': 'design-1',
      'name': 'Native Design',
      'product_id': 'product-1',
      'design': {
        'format': 'fresh_builder_design',
        'version': 5,
      },
      'created_at': '2026-10-08T12:00:00Z',
      'updated_at': '2026-10-08T13:00:00Z',
    });

    expect(design.id, 'design-1');
    expect(design.name, 'Native Design');
    expect(design.productId, 'product-1');
    expect(design.design['format'], 'fresh_builder_design');
    expect(design.design['version'], 5);
    expect(design.updatedAt, isNotNull);
  });

  test('normalizes malformed design payload to an empty map', () {
    final design = BuilderCloudSavedDesign.fromJson({
      'id': 'design-2',
      'name': 'Legacy',
      'design': 'not-json-object',
    });

    expect(design.design, isEmpty);
  });
}
