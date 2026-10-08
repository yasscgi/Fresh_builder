import 'dart:async';

import 'package:flutter/foundation.dart';

import '../rust/api/rig.dart';
import 'native_viewport_controller.dart';

class NativeRigController extends ChangeNotifier {
  NativeRigSession? _session;
  BridgeRigState? _state;
  BridgeRigPoseSnapshot? _snapshot;
  Future<void>? _initialization;
  Future<void>? _fkFlush;
  Future<void>? _ikFlush;
  _PendingFk? _pendingFk;
  _PendingIk? _pendingIk;
  String? _error;

  BridgeRigMode get mode => _state?.mode ?? BridgeRigMode.none;
  bool get handOpen => (_state?.handOpen ?? 1.0) >= 0.5;
  bool get canUndo => _state?.canUndo ?? false;
  bool get canRedo => _state?.canRedo ?? false;
  bool get gestureActive => _state?.gestureActive ?? false;
  String? get selectedBone => _state?.selectedBone;
  String? get selectedEffector => _state?.selectedEffector;
  BridgeEuler? get selectedFkRotation => _state?.selectedFkRotation;
  BridgeRigPoseSnapshot? get snapshot => _snapshot;
  String? get error => _error;
  bool get ready => _session != null && _error == null;

  Future<void> ensureInitialized() {
    if (_session != null) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final session = await NativeRigSession.create();
      _session = session;
      _state = await session.state();
      _snapshot = await session.poseSnapshot();
      _error = null;
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _initialization = null;
      notifyListeners();
    }
  }

  Future<void> reset() async {
    _pendingFk = null;
    _pendingIk = null;
    await _fkFlush;
    await _ikFlush;
    final session = await _requireSession();
    try {
      _state = await session.reset();
      _snapshot = await session.poseSnapshot();
      _error = null;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> setMode(BridgeRigMode mode) async {
    final session = await _requireSession();
    try {
      _state = await session.setMode(mode: mode);
      _snapshot = await session.poseSnapshot();
      _error = null;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> selectBone(String? bone) async {
    final session = await _requireSession();
    try {
      _state = await session.selectBone(bone: bone);
      _snapshot = await session.poseSnapshot();
      _error = null;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> selectEffector(String? effector) async {
    final session = await _requireSession();
    try {
      _state = await session.selectEffector(effector: effector);
      _snapshot = await session.poseSnapshot();
      _error = null;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> setHandOpen(bool open) async {
    final session = await _requireSession();
    try {
      _state = await session.setHandOpen(open: open);
      _snapshot = await session.poseSnapshot();
      _error = null;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> beginGesture() async {
    await _flushPendingFk();
    await _flushPendingIk();
    final session = await _requireSession();
    try {
      _state = await session.beginGesture();
      _error = null;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  void updateFkRotation({
    required NativeViewportController viewport,
    required String sceneKey,
    required String bone,
    required double x,
    required double y,
    required double z,
  }) {
    if (sceneKey.isEmpty ||
        bone.trim().isEmpty ||
        !x.isFinite ||
        !y.isFinite ||
        !z.isFinite) {
      return;
    }

    _pendingFk = _PendingFk(
      viewport: viewport,
      sceneKey: sceneKey,
      bone: bone,
      x: x,
      y: y,
      z: z,
    );
    _ensureFkFlush();
  }

  void updateIkTarget({
    required NativeViewportController viewport,
    required String sceneKey,
    required String effector,
    required String upper,
    required String lower,
    required String end,
    required double targetX,
    required double targetY,
    required double targetZ,
    required double poleX,
    required double poleY,
    required double poleZ,
  }) {
    if (sceneKey.isEmpty ||
        effector.trim().isEmpty ||
        upper.trim().isEmpty ||
        lower.trim().isEmpty ||
        end.trim().isEmpty) {
      return;
    }
    final values = [
      targetX,
      targetY,
      targetZ,
      poleX,
      poleY,
      poleZ,
    ];
    if (values.any((value) => !value.isFinite)) return;

    _pendingIk = _PendingIk(
      viewport: viewport,
      sceneKey: sceneKey,
      effector: effector,
      upper: upper,
      lower: lower,
      end: end,
      targetX: targetX,
      targetY: targetY,
      targetZ: targetZ,
      poleX: poleX,
      poleY: poleY,
      poleZ: poleZ,
    );
    _ensureIkFlush();
  }

  Future<void> commitGesture() async {
    await _flushPendingFk();
    await _flushPendingIk();
    final session = await _requireSession();
    try {
      _state = await session.commitGesture();
      _snapshot = await session.poseSnapshot();
      _error = null;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> cancelGesture({
    required NativeViewportController viewport,
    required String sceneKey,
  }) async {
    _pendingFk = null;
    _pendingIk = null;
    await _fkFlush;
    await _ikFlush;
    final session = await _requireSession();
    try {
      _state = await session.cancelGesture();
      _snapshot = await session.poseSnapshot();
      await syncViewport(viewport, sceneKey);
      _error = null;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> undo({
    required NativeViewportController viewport,
    required String sceneKey,
  }) async {
    _pendingFk = null;
    _pendingIk = null;
    await _fkFlush;
    await _ikFlush;
    final session = await _requireSession();
    try {
      _state = await session.undo();
      _snapshot = await session.poseSnapshot();
      await syncViewport(viewport, sceneKey);
      _error = null;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> redo({
    required NativeViewportController viewport,
    required String sceneKey,
  }) async {
    _pendingFk = null;
    _pendingIk = null;
    await _fkFlush;
    await _ikFlush;
    final session = await _requireSession();
    try {
      _state = await session.redo();
      _snapshot = await session.poseSnapshot();
      await syncViewport(viewport, sceneKey);
      _error = null;
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  void _ensureFkFlush() {
    if (_fkFlush != null) return;
    final future = _flushFkLoop();
    _fkFlush = future;
    unawaited(
      future.whenComplete(() {
        _fkFlush = null;
        if (_pendingFk != null) {
          _ensureFkFlush();
        }
      }),
    );
  }

  Future<void> _flushPendingFk() async {
    while (_pendingFk != null || _fkFlush != null) {
      if (_pendingFk != null && _fkFlush == null) {
        _ensureFkFlush();
      }
      final active = _fkFlush;
      if (active != null) {
        await active;
      }
    }
  }

  Future<void> _flushFkLoop() async {
    final session = await _requireSession();

    try {
      while (true) {
        final pending = _pendingFk;
        if (pending == null) break;
        _pendingFk = null;

        _state = await session.updateFkRotation(
          bone: pending.bone,
          x: pending.x,
          y: pending.y,
          z: pending.z,
        );
        await pending.viewport.setSceneFkRotation(
          sceneKey: pending.sceneKey,
          bone: pending.bone,
          x: pending.x,
          y: pending.y,
          z: pending.z,
        );
      }
      _error = null;
      notifyListeners();
    } catch (error) {
      _pendingFk = null;
      _setError(error);
    }
  }

  void _ensureIkFlush() {
    if (_ikFlush != null) return;
    final future = _flushIkLoop();
    _ikFlush = future;
    unawaited(
      future.whenComplete(() {
        _ikFlush = null;
        if (_pendingIk != null) {
          _ensureIkFlush();
        }
      }),
    );
  }

  Future<void> _flushPendingIk() async {
    while (_pendingIk != null || _ikFlush != null) {
      if (_pendingIk != null && _ikFlush == null) {
        _ensureIkFlush();
      }
      final active = _ikFlush;
      if (active != null) {
        await active;
      }
    }
  }

  Future<void> _flushIkLoop() async {
    final session = await _requireSession();

    try {
      while (true) {
        final pending = _pendingIk;
        if (pending == null) break;
        _pendingIk = null;

        _state = await session.updateIkTarget(
          effector: pending.effector,
          upper: pending.upper,
          lower: pending.lower,
          end: pending.end,
          targetX: pending.targetX,
          targetY: pending.targetY,
          targetZ: pending.targetZ,
          poleX: pending.poleX,
          poleY: pending.poleY,
          poleZ: pending.poleZ,
        );
        await pending.viewport.setSceneTwoBoneIk(
          sceneKey: pending.sceneKey,
          upper: pending.upper,
          lower: pending.lower,
          end: pending.end,
          targetX: pending.targetX,
          targetY: pending.targetY,
          targetZ: pending.targetZ,
          poleX: pending.poleX,
          poleY: pending.poleY,
          poleZ: pending.poleZ,
        );
      }
      _error = null;
      notifyListeners();
    } catch (error) {
      _pendingIk = null;
      _setError(error);
    }
  }

  Future<void> restoreDesignPose({
    required NativeViewportController viewport,
    required String sceneKey,
    required Map<String, dynamic> pose,
  }) async {
    await reset();
    if (!viewport.hasLoadedScene(sceneKey)) return;

    await viewport.resetScenePose(sceneKey);
    await beginGesture();

    for (final raw in (pose['fk'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final row = raw.map((key, value) => MapEntry(key.toString(), value));
      final bone = row['bone']?.toString() ?? '';
      final rotation = row['rotation'] as List? ?? const [];
      if (bone.isEmpty || rotation.length < 3) continue;
      final x = (rotation[0] as num?)?.toDouble() ?? 0.0;
      final y = (rotation[1] as num?)?.toDouble() ?? 0.0;
      final z = (rotation[2] as num?)?.toDouble() ?? 0.0;
      updateFkRotation(
        viewport: viewport,
        sceneKey: sceneKey,
        bone: bone,
        x: x,
        y: y,
        z: z,
      );
    }

    for (final raw in (pose['ik'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final row = raw.map((key, value) => MapEntry(key.toString(), value));
      final effector = row['effector']?.toString() ?? '';
      final upper = row['upper']?.toString() ?? '';
      final lower = row['lower']?.toString() ?? '';
      final end = row['end']?.toString() ?? '';
      final target = row['target'] as List? ?? const [];
      final pole = row['pole'] as List? ?? const [];
      if (effector.isEmpty ||
          upper.isEmpty ||
          lower.isEmpty ||
          end.isEmpty ||
          target.length < 3 ||
          pole.length < 3) {
        continue;
      }
      updateIkTarget(
        viewport: viewport,
        sceneKey: sceneKey,
        effector: effector,
        upper: upper,
        lower: lower,
        end: end,
        targetX: (target[0] as num?)?.toDouble() ?? 0.0,
        targetY: (target[1] as num?)?.toDouble() ?? 0.0,
        targetZ: (target[2] as num?)?.toDouble() ?? 0.0,
        poleX: (pole[0] as num?)?.toDouble() ?? 0.0,
        poleY: (pole[1] as num?)?.toDouble() ?? 0.0,
        poleZ: (pole[2] as num?)?.toDouble() ?? 0.0,
      );
    }

    await commitGesture();

    final handOpen =
        ((pose['hand_open'] as num?)?.toDouble() ?? 1.0) >= 0.5;
    await setHandOpen(handOpen);

    final selectedBone = pose['selected_bone']?.toString();
    if (selectedBone != null && selectedBone.isNotEmpty) {
      await selectBone(selectedBone);
    }
    final selectedEffector = pose['selected_effector']?.toString();
    if (selectedEffector != null && selectedEffector.isNotEmpty) {
      await selectEffector(selectedEffector);
    }

    final mode = switch (pose['mode']?.toString().toLowerCase()) {
      'ik' => BridgeRigMode.ik,
      'fk' => BridgeRigMode.fk,
      _ => BridgeRigMode.none,
    };
    await setMode(mode);
    await syncViewport(viewport, sceneKey);
  }

  Future<void> syncViewport(
    NativeViewportController viewport,
    String sceneKey,
  ) async {
    if (sceneKey.isEmpty) return;
    final snapshot = _snapshot;
    if (snapshot == null) return;

    await viewport.resetScenePose(sceneKey);
    for (final fk in snapshot.fk) {
      await viewport.setSceneFkRotation(
        sceneKey: sceneKey,
        bone: fk.bone,
        x: fk.rotation.x,
        y: fk.rotation.y,
        z: fk.rotation.z,
      );
    }
    for (final ik in snapshot.ik) {
      await viewport.setSceneTwoBoneIk(
        sceneKey: sceneKey,
        upper: ik.upper,
        lower: ik.lower,
        end: ik.end,
        targetX: ik.target.x,
        targetY: ik.target.y,
        targetZ: ik.target.z,
        poleX: ik.pole.x,
        poleY: ik.pole.y,
        poleZ: ik.pole.z,
      );
    }
    await viewport.setSceneHandOpen(
      sceneKey: sceneKey,
      openAmount: snapshot.handOpen,
    );
    await viewport.refreshJointScreenPoints(sceneKey);
  }

  Future<NativeRigSession> _requireSession() async {
    await ensureInitialized();
    final session = _session;
    if (session == null) {
      throw StateError(_error ?? 'Native rig session is unavailable');
    }
    return session;
  }

  void _setError(Object error) {
    _error = error.toString();
    notifyListeners();
  }

  @override
  void dispose() {
    _pendingFk = null;
    _pendingIk = null;
    _session?.dispose();
    _session = null;
    super.dispose();
  }
}

class _PendingFk {
  const _PendingFk({
    required this.viewport,
    required this.sceneKey,
    required this.bone,
    required this.x,
    required this.y,
    required this.z,
  });

  final NativeViewportController viewport;
  final String sceneKey;
  final String bone;
  final double x;
  final double y;
  final double z;
}


class _PendingIk {
  const _PendingIk({
    required this.viewport,
    required this.sceneKey,
    required this.effector,
    required this.upper,
    required this.lower,
    required this.end,
    required this.targetX,
    required this.targetY,
    required this.targetZ,
    required this.poleX,
    required this.poleY,
    required this.poleZ,
  });

  final NativeViewportController viewport;
  final String sceneKey;
  final String effector;
  final String upper;
  final String lower;
  final String end;
  final double targetX;
  final double targetY;
  final double targetZ;
  final double poleX;
  final double poleY;
  final double poleZ;
}
