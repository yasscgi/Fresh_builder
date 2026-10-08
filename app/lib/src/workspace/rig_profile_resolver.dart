import '../cloud/builder_cloud_models.dart';

class RigBoneConstraintBinding {
  const RigBoneConstraintBinding({
    required this.bone,
    required this.primaryAxis,
    required this.hingeAxis,
    required this.allowedAxes,
    required this.rotationLimits,
    required this.source,
  });

  final String bone;
  final List<double>? primaryAxis;
  final List<double>? hingeAxis;
  final Set<String> allowedAxes;
  final Map<String, ({double min, double max})> rotationLimits;
  final String source;

  bool allows(String axis) => allowedAxes.contains(axis.toLowerCase());

  double clamp(String axis, double value) {
    final limit = rotationLimits[axis.toLowerCase()];
    if (limit == null || !value.isFinite) return value;
    return value.clamp(limit.min, limit.max);
  }
}

Map<String, RigBoneConstraintBinding> resolveRigBoneConstraints({
  required BuilderCloudData? data,
}) {
  final authored = _authoredRigMaps(data);
  for (final candidate in authored) {
    final constraints = _parseRigBoneConstraints(candidate);
    if (constraints.isNotEmpty) return constraints;
  }
  return const <String, RigBoneConstraintBinding>{};
}

Map<String, RigBoneConstraintBinding> _parseRigBoneConstraints(JsonMap rig) {
  final bones = rig['bones'];
  if (bones is! List) {
    return const <String, RigBoneConstraintBinding>{};
  }

  final out = <String, RigBoneConstraintBinding>{};
  for (final item in bones) {
    final row = jsonMap(item);
    final source = _firstString(
      row,
      ['source_name', 'sourceName', 'source', 'bone', 'bone_name', 'boneName'],
    );
    if (source == null || source.isEmpty) continue;

    final primary = _optionalVec3(
      row['primary_axis'] ?? row['primaryAxis'],
    );
    final hinge = _optionalVec3(
      row['hinge_axis'] ?? row['hingeAxis'],
    );
    final allowed = hinge == null
        ? const <String>{'x', 'y', 'z'}
        : <String>{_dominantAxis(hinge)};

    out[source] = RigBoneConstraintBinding(
      bone: source,
      primaryAxis: primary,
      hingeAxis: hinge,
      allowedAxes: allowed,
      rotationLimits: _rotationLimits(
        row['rotation_limits'] ?? row['rotationLimits'] ?? row['limits'],
      ),
      source: 'rig_v3',
    );
  }
  return out;
}

Map<String, ({double min, double max})> _rotationLimits(Object? value) {
  final map = jsonMap(value);
  if (map.isEmpty) return const <String, ({double min, double max})>{};

  final out = <String, ({double min, double max})>{};
  for (final axis in const ['x', 'y', 'z']) {
    final raw = map[axis] ?? map[axis.toUpperCase()];
    double? min;
    double? max;

    if (raw is List && raw.length >= 2) {
      min = (raw[0] as num?)?.toDouble();
      max = (raw[1] as num?)?.toDouble();
    } else {
      final row = jsonMap(raw);
      min = (row['min'] as num?)?.toDouble();
      max = (row['max'] as num?)?.toDouble();
    }

    if (min == null || max == null || !min.isFinite || !max.isFinite) continue;
    if (min > max) {
      final swap = min;
      min = max;
      max = swap;
    }
    out[axis] = (min: min, max: max);
  }
  return out;
}

List<double>? _optionalVec3(Object? value) {
  if (value == null) return null;
  final parsed = _vec3(value, fallback: const [double.nan, double.nan, double.nan]);
  if (parsed.any((component) => !component.isFinite)) return null;
  final lengthSquared = parsed.fold<double>(
    0,
    (sum, component) => sum + component * component,
  );
  if (!lengthSquared.isFinite || lengthSquared <= 1.0e-12) return null;
  return parsed;
}

String _dominantAxis(List<double> vector) {
  final ax = vector[0].abs();
  final ay = vector[1].abs();
  final az = vector[2].abs();
  if (ax >= ay && ax >= az) return 'x';
  if (ay >= ax && ay >= az) return 'y';
  return 'z';
}

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
