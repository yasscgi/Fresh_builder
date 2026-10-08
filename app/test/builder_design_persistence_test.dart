import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_builder/src/workspace/builder_design_persistence.dart';

void main() {
  test('Design v5 parser restores selections transforms and pose', () {
    final snapshot = BuilderDesignSnapshot.fromJson({
      'format': 'fresh_builder_design',
      'version': 5,
      'product_id': 'product-1',
      'assets': [
        {
          'scene_key': 'role:base_character',
          'asset_id': 'asset-base',
          'variation_id': null,
        },
        {
          'scene_key': 'slot:hat',
          'asset_id': 'asset-hat',
          'variation_id': 'variation-red',
        },
      ],
      'asset_transforms': [
        {
          'scene_key': 'slot:hat',
          'translation': [0.01, 0.02, 0.03],
          'rotation_xyz': [0.1, 0.2, 0.3],
          'scale': 1.25,
        },
      ],
      'pose': {
        'mode': 'fk',
        'hand_open': 0.0,
        'selected_bone': 'mixamorig:LeftArm',
        'fk': [
          {
            'bone': 'mixamorig:LeftArm',
            'rotation': [0.1, 0.2, 0.3],
          },
        ],
        'ik': [],
      },
    });

    expect(snapshot.productId, 'product-1');
    expect(snapshot.assets, hasLength(2));
    expect(snapshot.assets.last.variationId, 'variation-red');
    final transform = snapshot.transforms['slot:hat'];
    expect(transform, isNotNull);
    expect(transform!.tx, 0.01);
    expect(transform.ty, 0.02);
    expect(transform.tz, 0.03);
    expect(transform.rx, 0.1);
    expect(transform.ry, 0.2);
    expect(transform.rz, 0.3);
    expect(transform.scale, 1.25);
    expect(snapshot.pose['mode'], 'fk');
    expect(snapshot.pose['hand_open'], 0.0);
  });

  test('Design v5 parser ignores malformed transform rows', () {
    final snapshot = BuilderDesignSnapshot.fromJson({
      'product_id': 'product-1',
      'assets': const [],
      'asset_transforms': [
        {
          'scene_key': 'bad',
          'translation': [0.0],
          'rotation_xyz': [0.0, 0.0, 0.0],
          'scale': -1.0,
        },
      ],
      'pose': const {},
    });

    expect(snapshot.transforms, isEmpty);
  });
}
