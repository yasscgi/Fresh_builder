import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_builder/src/cloud/builder_cloud_models.dart';
import 'package:fresh_builder/src/workspace/rig_profile_resolver.dart';

void main() {
  test('prefers authored Rig V3 chains from builder config', () {
    final data = BuilderCloudData(
      config: BuilderCloudConfig(
        productId: 'p1',
        mode: 'character',
        config: {
          'rigProfile': {
            'format': 'freshstl_mixamo_rig_v3',
            'chains': [
              {
                'effector': 'LeftFoot',
                'upper': 'CustomThigh.L',
                'lower': 'CustomShin.L',
                'end': 'CustomFoot.L',
                'poleDirection': [0, 0, 1],
              },
            ],
          },
        },
      ),
      categories: const [],
      assets: const [],
      articulatedChains: const [],
      jointStandards: const [],
      surfaceZones: const [],
    );

    final chains = resolveIkChains(
      data: data,
      jointNames: const ['mixamorig:LeftUpLeg', 'mixamorig:LeftLeg', 'mixamorig:LeftFoot'],
    );

    expect(chains, hasLength(1));
    expect(chains.single.source, 'rig_v3');
    expect(chains.single.upper, 'CustomThigh.L');
    expect(chains.single.lower, 'CustomShin.L');
    expect(chains.single.end, 'CustomFoot.L');
  });

  test('infers four standard Mixamo chains when metadata is absent', () {
    const joints = [
      'mixamorig:LeftArm',
      'mixamorig:LeftForeArm',
      'mixamorig:LeftHand',
      'mixamorig:RightArm',
      'mixamorig:RightForeArm',
      'mixamorig:RightHand',
      'mixamorig:LeftUpLeg',
      'mixamorig:LeftLeg',
      'mixamorig:LeftFoot',
      'mixamorig:RightUpLeg',
      'mixamorig:RightLeg',
      'mixamorig:RightFoot',
    ];

    final chains = resolveIkChains(data: null, jointNames: joints);

    expect(chains.map((item) => item.effector).toSet(), {
      'LeftHand',
      'RightHand',
      'LeftFoot',
      'RightFoot',
    });
    expect(chains.every((item) => item.source == 'mixamo_fallback'), isTrue);
  });

  test('does not invent incomplete chains', () {
    final chains = inferMixamoIkChains(const [
      'LeftArm',
      'LeftHand',
      'RightUpLeg',
      'RightLeg',
    ]);

    expect(chains, isEmpty);
  });
}
