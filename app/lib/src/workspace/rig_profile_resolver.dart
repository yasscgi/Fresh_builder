import '../cloud/builder_cloud_models.dart';

class IkChainBinding {
  const IkChainBinding({
    required this.effector,
    required this.upper,
    required this.lower,
    required this.end,
    required this.poleDirection,
    required this.source,
  });

  final String effector;
  final String upper;
  final String lower;
  final String end;
  final List<double> poleDirection;
  final String source;
}

List<IkChainBinding> resolveIkChains({
  required BuilderCloudData? data,
  required List<String> jointNames,
}) {
  final authored = _authoredRigMaps(data);
  for (final candidate in authored) {
    final chains = _parseRigChains(candidate);
    if (chains.isNotEmpty) return chains;
  }
  return inferMixamoIkChains(jointNames);
}

List<JsonMap> _authoredRigMaps(BuilderCloudData? data) {
  if (data == null) return const <JsonMap>[];
  final candidates = <JsonMap>[];

  final config = data.config?.config;
  if (config != null && config.isNotEmpty) {
    candidates.addAll(_findRigMaps(config));
  }

  for (final asset in data.assets) {
    final role = asset.role.trim().toLowerCase();
    if (role != 'base_character' && asset.type != 'base_character') continue;
    candidates.addAll(_findRigMaps(asset.metadata));
    for (final variation in asset.variations) {
      candidates.addAll(_findRigMaps(variation.metadata));
    }
  }
  return candidates;
}

List<JsonMap> _findRigMaps(JsonMap root) {
  final found = <JsonMap>[];

  void visit(Object? value) {
    final map = jsonMap(value);
    if (map.isNotEmpty) {
      final format = (map['format'] ?? map['rig_format'] ?? map['rigFormat'])
          ?.toString()
          .trim()
          .toLowerCase();
      final hasChains = map['chains'] is List ||
          map['ik_chains'] is List ||
          map['ikChains'] is List;
      if (format == 'freshstl_mixamo_rig_v3' || hasChains) {
        found.add(map);
      }
      for (final child in map.values) {
        if (child is Map || child is List) visit(child);
      }
      return;
    }
    if (value is List) {
      for (final child in value) {
        visit(child);
      }
    }
  }

  visit(root);
  return found;
}

List<IkChainBinding> _parseRigChains(JsonMap rig) {
  final raw = rig['chains'] ?? rig['ik_chains'] ?? rig['ikChains'];
  if (raw is! List) return const <IkChainBinding>[];

  final semanticToSource = <String, String>{};
  final bones = rig['bones'];
  if (bones is List) {
    for (final item in bones) {
      final row = jsonMap(item);
      final semantic = _firstString(row, ['semantic', 'id', 'name']);
      final source = _firstString(
        row,
        ['source_name', 'sourceName', 'source', 'bone', 'bone_name', 'boneName'],
      );
      if (semantic != null && source != null) {
        semanticToSource[_normalizeBone(semantic)] = source;
      }
    }
  }

  String? resolveBone(String? value) {
    if (value == null || value.isEmpty) return null;
    return semanticToSource[_normalizeBone(value)] ?? value;
  }

  final out = <IkChainBinding>[];
  for (final item in raw) {
    final row = jsonMap(item);
    final effector = _firstString(row, ['effector', 'name', 'id']);
    final upper = resolveBone(_firstString(row, ['upper', 'upper_bone', 'upperBone']));
    final lower = resolveBone(_firstString(row, ['lower', 'lower_bone', 'lowerBone']));
    final end = resolveBone(
      _firstString(row, ['end', 'end_bone', 'endBone', 'target_bone', 'targetBone']),
    );
    if ([effector, upper, lower, end].any((value) => value == null || value.isEmpty)) {
      continue;
    }

    out.add(
      IkChainBinding(
        effector: effector!,
        upper: upper!,
        lower: lower!,
        end: end!,
        poleDirection: _vec3(
          row['pole_direction'] ?? row['poleDirection'] ?? row['pole'],
          fallback: const [0.0, 0.0, 1.0],
        ),
        source: 'rig_v3',
      ),
    );
  }
  return out;
}

List<IkChainBinding> inferMixamoIkChains(List<String> jointNames) {
  final chains = <IkChainBinding>[];

  String? find(List<String> semantics) {
    for (final semantic in semantics) {
      final normalizedSemantic = _normalizeBone(semantic);
      for (final joint in jointNames) {
        final normalizedJoint = _normalizeBone(joint);
        if (normalizedJoint == normalizedSemantic ||
            normalizedJoint.endsWith(normalizedSemantic)) {
          return joint;
        }
      }
    }
    return null;
  }

  void add({
    required String effector,
    required List<String> upperNames,
    required List<String> lowerNames,
    required List<String> endNames,
    required List<double> pole,
  }) {
    final upper = find(upperNames);
    final lower = find(lowerNames);
    final end = find(endNames);
    if (upper == null || lower == null || end == null) return;
    chains.add(
      IkChainBinding(
        effector: effector,
        upper: upper,
        lower: lower,
        end: end,
        poleDirection: pole,
        source: 'mixamo_fallback',
      ),
    );
  }

  add(
    effector: 'LeftHand',
    upperNames: const ['LeftArm', 'LeftUpperArm'],
    lowerNames: const ['LeftForeArm', 'LeftLowerArm'],
    endNames: const ['LeftHand'],
    pole: const [0.0, 0.0, -1.0],
  );
  add(
    effector: 'RightHand',
    upperNames: const ['RightArm', 'RightUpperArm'],
    lowerNames: const ['RightForeArm', 'RightLowerArm'],
    endNames: const ['RightHand'],
    pole: const [0.0, 0.0, -1.0],
  );
  add(
    effector: 'LeftFoot',
    upperNames: const ['LeftUpLeg', 'LeftUpperLeg'],
    lowerNames: const ['LeftLeg', 'LeftLowerLeg'],
    endNames: const ['LeftFoot'],
    pole: const [0.0, 0.0, 1.0],
  );
  add(
    effector: 'RightFoot',
    upperNames: const ['RightUpLeg', 'RightUpperLeg'],
    lowerNames: const ['RightLeg', 'RightLowerLeg'],
    endNames: const ['RightFoot'],
    pole: const [0.0, 0.0, 1.0],
  );

  return chains;
}

String? _firstString(JsonMap row, List<String> keys) {
  for (final key in keys) {
    final value = row[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

List<double> _vec3(Object? value, {required List<double> fallback}) {
  if (value is List && value.length >= 3) {
    final x = (value[0] as num?)?.toDouble();
    final y = (value[1] as num?)?.toDouble();
    final z = (value[2] as num?)?.toDouble();
    if (x != null && y != null && z != null && x.isFinite && y.isFinite && z.isFinite) {
      return [x, y, z];
    }
  }
  final map = jsonMap(value);
  if (map.isNotEmpty) {
    final x = (map['x'] as num?)?.toDouble();
    final y = (map['y'] as num?)?.toDouble();
    final z = (map['z'] as num?)?.toDouble();
    if (x != null && y != null && z != null && x.isFinite && y.isFinite && z.isFinite) {
      return [x, y, z];
    }
  }
  return List<double>.of(fallback);
}

String _normalizeBone(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
