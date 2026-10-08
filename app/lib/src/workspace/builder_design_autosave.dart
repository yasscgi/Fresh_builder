import 'dart:async';

import '../cloud/builder_cloud_models.dart';
import 'builder_design_persistence.dart';
import 'native_rig_controller.dart';
import 'native_viewport_controller.dart';

final class BuilderDesignAutosaveController {
  BuilderDesignAutosaveController({
    BuilderDesignPersistence? persistence,
    this.delay = const Duration(milliseconds: 900),
  }) : _persistence = persistence ?? const BuilderDesignPersistence();

  final BuilderDesignPersistence _persistence;
  final Duration delay;

  Timer? _timer;
  int _generation = 0;
  Future<void>? _writeTail;

  bool get pending => _timer?.isActive == true || _writeTail != null;

  void schedule({
    required String productId,
    required String productName,
    required Map<String, BuilderAssetChoice> sceneSelections,
    required NativeViewportController viewport,
    required NativeRigController rig,
  }) {
    _generation += 1;
    final generation = _generation;
    _timer?.cancel();
    _timer = Timer(delay, () {
      final snapshotSelections =
          Map<String, BuilderAssetChoice>.from(sceneSelections);
      _enqueue(
        generation: generation,
        productId: productId,
        productName: productName,
        sceneSelections: snapshotSelections,
        viewport: viewport,
        rig: rig,
      );
    });
  }

  Future<void> flush({
    required String productId,
    required String productName,
    required Map<String, BuilderAssetChoice> sceneSelections,
    required NativeViewportController viewport,
    required NativeRigController rig,
  }) async {
    _timer?.cancel();
    _timer = null;
    _generation += 1;
    final generation = _generation;
    _enqueue(
      generation: generation,
      productId: productId,
      productName: productName,
      sceneSelections: Map<String, BuilderAssetChoice>.from(sceneSelections),
      viewport: viewport,
      rig: rig,
    );
    await _writeTail;
  }

  void _enqueue({
    required int generation,
    required String productId,
    required String productName,
    required Map<String, BuilderAssetChoice> sceneSelections,
    required NativeViewportController viewport,
    required NativeRigController rig,
  }) {
    final previous = _writeTail ?? Future<void>.value();
    final next = previous.then((_) async {
      if (generation < _generation) return;
      await _persistence.saveSnapshot(
        productId: productId,
        productName: productName,
        sceneSelections: sceneSelections,
        viewport: viewport,
        rig: rig,
      );
    }).catchError((Object _) {
      // Autosave is best-effort and must never surface as an uncaught
      // asynchronous exception. Explicit Save Design still reports errors.
    });

    _writeTail = next;
    next.whenComplete(() {
      if (identical(_writeTail, next)) {
        _writeTail = null;
      }
    });
  }

  void cancel() {
    _generation += 1;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    cancel();
  }
}
