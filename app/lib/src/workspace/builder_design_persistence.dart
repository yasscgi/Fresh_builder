import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../cloud/builder_cloud_models.dart';
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
