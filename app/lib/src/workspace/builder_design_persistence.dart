import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../cloud/builder_cloud_models.dart';
import '../cloud/builder_design_cloud_repository.dart';
import 'native_rig_controller.dart';
import 'native_viewport_controller.dart';

final class BuilderDesignPersistence {
  const BuilderDesignPersistence();

  Map<String, dynamic> buildSnapshot({
    required String productId,
    required Map<String, BuilderAssetChoice> sceneSelections,
    required NativeViewportController viewport,
    required NativeRigController rig,
  }) {
    final snapshot = rig.snapshot;
    final transforms = viewport.sceneTransformsSnapshot;

    return <String, dynamic>{
      'format': 'fresh_builder_design',
      'version': 5,
      'product_id': productId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'assets': [
        for (final entry in sceneSelections.entries)
          <String, dynamic>{
            'scene_key': entry.key,
            'asset_id': entry.value.assetId,
            'variation_id': entry.value.variationId,
            'category_id': entry.value.asset.categoryId,
            'category_slug': entry.value.asset.categorySlug,
            'role': entry.value.asset.role,
          },
      ],
      'asset_transforms': [
        for (final entry in transforms.entries)
          <String, dynamic>{
            'scene_key': entry.key,
            'translation': [
              entry.value.tx,
              entry.value.ty,
              entry.value.tz,
            ],
            'rotation_xyz': [
              entry.value.rx,
              entry.value.ry,
              entry.value.rz,
            ],
            'scale': entry.value.scale,
          },
      ],
      'pose': snapshot == null
          ? <String, dynamic>{
              'mode': 'none',
              'hand_open': 1.0,
              'fk': const [],
              'ik': const [],
            }
          : <String, dynamic>{
              'mode': snapshot.mode.name,
              'selected_bone': snapshot.selectedBone,
              'selected_effector': snapshot.selectedEffector,
              'hand_open': snapshot.handOpen,
              'fk': [
                for (final item in snapshot.fk)
                  <String, dynamic>{
                    'bone': item.bone,
                    'rotation': [
                      item.rotation.x,
                      item.rotation.y,
                      item.rotation.z,
                    ],
                  },
              ],
              'ik': [
                for (final item in snapshot.ik)
                  <String, dynamic>{
                    'effector': item.effector,
                    'upper': item.upper,
                    'lower': item.lower,
                    'end': item.end,
                    'target': [
                      item.target.x,
                      item.target.y,
                      item.target.z,
                    ],
                    'pole': [
                      item.pole.x,
                      item.pole.y,
                      item.pole.z,
                    ],
                  },
              ],
            },
    };
  }


  Future<String?> saveCloudSnapshot({
    required String productId,
    required String productName,
    required Map<String, BuilderAssetChoice> sceneSelections,
    required NativeViewportController viewport,
    required NativeRigController rig,
    BuilderDesignCloudRepository? repository,
  }) async {
    final cloud = repository ?? BuilderDesignCloudRepository();
    if (!cloud.signedIn) return null;

    final design = buildSnapshot(
      productId: productId,
      sceneSelections: sceneSelections,
      viewport: viewport,
      rig: rig,
    );
    return cloud.saveDesign(
      productId: productId,
      name: '$productName · Native',
      design: design,
    );
  }

  Future<BuilderDesignSnapshot?> loadBestSnapshot({
    required String productId,
    required String productName,
    BuilderDesignCloudRepository? repository,
  }) async {
    final cloud = repository ?? BuilderDesignCloudRepository();
    if (cloud.signedIn) {
      final latest = await cloud.latestDesign(productId: productId);
      final design = latest?.design;
      if (design != null &&
          design['format'] == 'fresh_builder_design' &&
          (design['version'] as num?)?.toInt() == 5) {
        return BuilderDesignSnapshot.fromJson(design);
      }
    }

    return loadSnapshot(productName: productName);
  }

  Future<BuilderDesignSnapshot?> loadSnapshot({
    required String productName,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final safeName = _safeName(productName);
    final fileName =
        '${safeName.isEmpty ? 'fresh-builder' : safeName}.freshbuilder.json';
    final path = '${directory.path}${Platform.pathSeparator}$fileName';
    final file = File(path);
    if (!await file.exists()) return null;

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Builder design root must be an object.');
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (json['format'] != 'fresh_builder_design') {
      throw const FormatException('Unsupported Builder design format.');
    }
    final version = (json['version'] as num?)?.toInt() ?? 0;
    if (version != 5) {
      throw FormatException('Unsupported Builder design version: $version');
    }
    return BuilderDesignSnapshot.fromJson(json);
  }

  Future<String> saveSnapshot({
    required String productId,
    required String productName,
    required Map<String, BuilderAssetChoice> sceneSelections,
    required NativeViewportController viewport,
    required NativeRigController rig,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final safeName = _safeName(productName);
    final fileName =
        '${safeName.isEmpty ? 'fresh-builder' : safeName}.freshbuilder.json';
    final path = '${directory.path}${Platform.pathSeparator}$fileName';
    final json = const JsonEncoder.withIndent('  ').convert(
      buildSnapshot(
        productId: productId,
        sceneSelections: sceneSelections,
        viewport: viewport,
        rig: rig,
      ),
    );
    await File(path).writeAsString(json, flush: true);
    return path;
  }

  Future<BuilderPrintValidationResult> validateCurrentPrint({
    required NativeViewportController viewport,
  }) async {
    final report = await viewport.validateCurrentPrint();
    if (report == null) {
      throw StateError('Native print validation is unavailable.');
    }
    return BuilderPrintValidationResult(
      meshCount: report.meshCount,
      triangleCount: report.triangleCount,
      degenerateTriangles: report.degenerateTriangles,
      boundaryEdges: report.boundaryEdges,
      nonManifoldEdges: report.nonManifoldEdges,
      invalidIndices: report.invalidIndices,
      inconsistentWindingEdges: report.inconsistentWindingEdges,
      connectedComponents: report.connectedComponents,
      sizeXmm: report.sizeXmm,
      sizeYmm: report.sizeYmm,
      sizeZmm: report.sizeZmm,
      watertight: report.watertight,
    );
  }

  Future<BuilderExportResult> exportCurrent3mf({
    required String productName,
    required NativeViewportController viewport,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final safeName = _safeName(productName);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName =
        '${safeName.isEmpty ? 'fresh-builder' : safeName}-$stamp.3mf';
    final path = '${directory.path}${Platform.pathSeparator}$fileName';

    final status = await viewport.exportCurrent3mf(path);
    if (status == null) {
      throw StateError('Native 3MF export is unavailable.');
    }
    return BuilderExportResult(
      path: status.path,
      sceneCount: status.sceneCount,
      meshCount: status.meshCount,
      triangleCount: status.triangleCount,
    );
  }

  Future<BuilderExportResult> exportCurrentStl({
    required String productName,
    required NativeViewportController viewport,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final safeName = _safeName(productName);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName =
        '${safeName.isEmpty ? 'fresh-builder' : safeName}-$stamp.stl';
    final path = '${directory.path}${Platform.pathSeparator}$fileName';

    final status = await viewport.exportCurrentStl(path);
    if (status == null) {
      throw StateError('Native STL export is unavailable.');
    }
    return BuilderExportResult(
      path: status.path,
      sceneCount: status.sceneCount,
      meshCount: status.meshCount,
      triangleCount: status.triangleCount,
    );
  }

  String _safeName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

final class BuilderExportResult {
  const BuilderExportResult({
    required this.path,
    required this.sceneCount,
    required this.meshCount,
    required this.triangleCount,
  });

  final String path;
  final int sceneCount;
  final int meshCount;
  final int triangleCount;
}


final class BuilderDesignSnapshot {
  const BuilderDesignSnapshot({
    required this.productId,
    required this.assets,
    required this.transforms,
    required this.pose,
  });

  final String productId;
  final List<BuilderSavedAsset> assets;
  final Map<String, NativeSceneTransform> transforms;
  final Map<String, dynamic> pose;

  factory BuilderDesignSnapshot.fromJson(Map<String, dynamic> json) {
    final assets = <BuilderSavedAsset>[];
    for (final raw in (json['assets'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final row = raw.map((key, value) => MapEntry(key.toString(), value));
      final sceneKey = row['scene_key']?.toString() ?? '';
      final assetId = row['asset_id']?.toString() ?? '';
      if (sceneKey.isEmpty || assetId.isEmpty) continue;
      assets.add(
        BuilderSavedAsset(
          sceneKey: sceneKey,
          assetId: assetId,
          variationId: row['variation_id']?.toString(),
        ),
      );
    }

    final transforms = <String, NativeSceneTransform>{};
    for (final raw in (json['asset_transforms'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final row = raw.map((key, value) => MapEntry(key.toString(), value));
      final sceneKey = row['scene_key']?.toString() ?? '';
      final translation = row['translation'] as List? ?? const [];
      final rotation = row['rotation_xyz'] as List? ?? const [];
      final scale = (row['scale'] as num?)?.toDouble() ?? 1.0;
      if (sceneKey.isEmpty ||
          translation.length < 3 ||
          rotation.length < 3 ||
          !scale.isFinite ||
          scale <= 0) {
        continue;
      }
      transforms[sceneKey] = NativeSceneTransform(
        tx: (translation[0] as num?)?.toDouble() ?? 0,
        ty: (translation[1] as num?)?.toDouble() ?? 0,
        tz: (translation[2] as num?)?.toDouble() ?? 0,
        rx: (rotation[0] as num?)?.toDouble() ?? 0,
        ry: (rotation[1] as num?)?.toDouble() ?? 0,
        rz: (rotation[2] as num?)?.toDouble() ?? 0,
        scale: scale,
      );
    }

    final rawPose = json['pose'];
    final pose = rawPose is Map
        ? rawPose.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    return BuilderDesignSnapshot(
      productId: json['product_id']?.toString() ?? '',
      assets: assets,
      transforms: transforms,
      pose: pose,
    );
  }
}

final class BuilderSavedAsset {
  const BuilderSavedAsset({
    required this.sceneKey,
    required this.assetId,
    required this.variationId,
  });

  final String sceneKey;
  final String assetId;
  final String? variationId;
}


final class BuilderPrintValidationResult {
  const BuilderPrintValidationResult({
    required this.meshCount,
    required this.triangleCount,
    required this.degenerateTriangles,
    required this.boundaryEdges,
    required this.nonManifoldEdges,
    required this.invalidIndices,
    required this.inconsistentWindingEdges,
    required this.connectedComponents,
    required this.sizeXmm,
    required this.sizeYmm,
    required this.sizeZmm,
    required this.watertight,
  });

  final int meshCount;
  final int triangleCount;
  final int degenerateTriangles;
  final int boundaryEdges;
  final int nonManifoldEdges;
  final int invalidIndices;
  final int inconsistentWindingEdges;
  final int connectedComponents;
  final double sizeXmm;
  final double sizeYmm;
  final double sizeZmm;
  final bool watertight;
}
