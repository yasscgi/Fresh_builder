import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fresh_builder_viewport_texture/fresh_builder_viewport_texture.dart';

import '../rust/api/builder.dart';

class NativeViewportController extends ChangeNotifier {
  NativeViewportSession? _session;
  final FreshBuilderViewportTexture _textureBridge =
      FreshBuilderViewportTexture();
  int? _textureId;
  String? _textureError;
  BridgeCameraState? _camera;
  NativeSceneStatus? _sceneStatus;
  String? _sceneError;
  String? _error;
  final Map<String, ({String path, double metersPerUnit})> _pendingScenes = {};
  final Set<String> _loadedSceneKeys = <String>{};
  final Map<String, List<String>> _jointNamesByScene = <String, List<String>>{};
  final Map<String, List<NativeJointScreenPoint>> _jointScreenPointsByScene =
      <String, List<NativeJointScreenPoint>>{};
  bool _initializing = false;
  bool _orbitInFlight = false;
  bool _zoomInFlight = false;
  double _pendingOrbitX = 0;
  double _pendingOrbitY = 0;
  double _pendingZoom = 0;
  int _width = 0;
  int _height = 0;

  bool get ready => _session != null && _error == null;
  bool get initializing => _initializing;
  String? get error => _error;
  BridgeCameraState? get camera => _camera;
  NativeSceneStatus? get sceneStatus => _sceneStatus;
  String? get sceneError => _sceneError;
  int? get textureId => _textureId;
  String? get textureError => _textureError;
  bool get textureAvailable => _textureId != null;
  int get physicalWidth => _width;
  int get physicalHeight => _height;
  bool hasLoadedScene(String sceneKey) => _loadedSceneKeys.contains(sceneKey);
  List<String> sceneJointNames(String sceneKey) =>
      List<String>.unmodifiable(_jointNamesByScene[sceneKey] ?? const <String>[]);
  List<NativeJointScreenPoint> sceneJointScreenPoints(String sceneKey) =>
      List<NativeJointScreenPoint>.unmodifiable(
        _jointScreenPointsByScene[sceneKey] ?? const <NativeJointScreenPoint>[],
      );

  Future<void> ensureInitialized({
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) async {
    final width = _physicalExtent(logicalWidth, devicePixelRatio);
    final height = _physicalExtent(logicalHeight, devicePixelRatio);

    if (_session != null) {
      await resize(
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        devicePixelRatio: devicePixelRatio,
      );
      return;
    }
    if (_initializing) return;

    _initializing = true;
    _error = null;
    notifyListeners();

    try {
      final session = await NativeViewportSession.create(
        width: width,
        height: height,
      );
      _session = session;
      _width = width;
      _height = height;
      _camera = await session.cameraState();
      await _ensureTexture();
      await session.renderFrame();
      await _markTextureFrame();
      await _loadPendingScenes();
    } catch (error) {
      _error = error.toString();
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> resize({
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) async {
    final session = _session;
    if (session == null) return;

    final width = _physicalExtent(logicalWidth, devicePixelRatio);
    final height = _physicalExtent(logicalHeight, devicePixelRatio);
    if (width == _width && height == _height) return;

    try {
      await session.resize(width: width, height: height);
      _width = width;
      _height = height;
      await _markTextureFrame();
      for (final sceneKey in _loadedSceneKeys) {
        await _refreshJointScreenPoints(sceneKey);
      }
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  void orbit(double deltaX, double deltaY, {double sensitivity = 0.008}) {
    if (_session == null || _error != null) return;
    _pendingOrbitX += deltaX;
    _pendingOrbitY += deltaY;
    if (!_orbitInFlight) {
      unawaited(_flushOrbit(sensitivity));
    }
  }

  Future<void> _flushOrbit(double sensitivity) async {
    final session = _session;
    if (session == null || _orbitInFlight) return;

    _orbitInFlight = true;
    try {
      while (_session != null &&
          (_pendingOrbitX.abs() > 0.0001 || _pendingOrbitY.abs() > 0.0001)) {
        final dx = _pendingOrbitX;
        final dy = _pendingOrbitY;
        _pendingOrbitX = 0;
        _pendingOrbitY = 0;

        _camera = await session.orbit(
          deltaX: dx,
          deltaY: dy,
          sensitivity: sensitivity,
        );
      }
      await _markTextureFrame();
      for (final sceneKey in _loadedSceneKeys) {
        await _refreshJointScreenPoints(sceneKey);
      }
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    } finally {
      _orbitInFlight = false;
      if (_pendingOrbitX.abs() > 0.0001 || _pendingOrbitY.abs() > 0.0001) {
        unawaited(_flushOrbit(sensitivity));
      }
    }
  }

  void zoom(double delta, {double sensitivity = 0.06}) {
    if (_session == null || _error != null) return;
    _pendingZoom += delta;
    if (!_zoomInFlight) {
      unawaited(_flushZoom(sensitivity));
    }
  }

  Future<void> _flushZoom(double sensitivity) async {
    final session = _session;
    if (session == null || _zoomInFlight) return;

    _zoomInFlight = true;
    try {
      while (_session != null && _pendingZoom.abs() > 0.0001) {
        final delta = _pendingZoom;
        _pendingZoom = 0;
        _camera = await session.zoom(
          delta: delta,
          sensitivity: sensitivity,
        );
      }
      await _markTextureFrame();
      for (final sceneKey in _loadedSceneKeys) {
        await _refreshJointScreenPoints(sceneKey);
      }
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    } finally {
      _zoomInFlight = false;
      if (_pendingZoom.abs() > 0.0001) {
        unawaited(_flushZoom(sensitivity));
      }
    }
  }

  Future<void> upsertLocalScene({
    required String sceneKey,
    required String path,
    required double metersPerUnit,
  }) async {
    if (sceneKey.isEmpty || path.isEmpty) return;

    _pendingScenes[sceneKey] = (
      path: path,
      metersPerUnit:
          metersPerUnit.isFinite && metersPerUnit > 0 ? metersPerUnit : 1,
    );

    if (_session == null) {
      notifyListeners();
      return;
    }
    await _loadSceneKey(sceneKey);
  }

  Future<void> _loadPendingScenes() async {
    if (_session == null || _pendingScenes.isEmpty) return;
    final keys = _pendingScenes.keys.toList(growable: false);
    for (final key in keys) {
      await _loadSceneKey(key);
    }
  }

  Future<void> _loadSceneKey(String sceneKey) async {
    final session = _session;
    final pending = _pendingScenes[sceneKey];
    if (session == null || pending == null) return;

    try {
      _sceneStatus = await session.upsertLocalScene(
        sceneKey: sceneKey,
        path: pending.path,
        metersPerUnit: pending.metersPerUnit,
      );
      if (_sceneStatus?.loadedToGpu == true) {
        _loadedSceneKeys.add(sceneKey);
        _jointNamesByScene[sceneKey] =
            await session.sceneJointNames(sceneKey: sceneKey);
        await _refreshJointScreenPoints(sceneKey);
      } else {
        _loadedSceneKeys.remove(sceneKey);
        _jointNamesByScene.remove(sceneKey);
        _jointScreenPointsByScene.remove(sceneKey);
      }
      _sceneError = null;
      await _markTextureFrame();
      notifyListeners();
    } catch (error) {
      _sceneError = error.toString();
      notifyListeners();
    }
  }

  Future<({double x, double y, double z})?> sceneJointWorldPosition(
    String sceneKey,
    String bone,
  ) async {
    final session = _session;
    if (session == null || _error != null) return null;
    try {
      final value = await session.sceneJointWorldPosition(
        sceneKey: sceneKey,
        bone: bone,
      );
      return (x: value.x, y: value.y, z: value.z);
    } catch (error) {
      _sceneError = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<({double x, double y, double z})?> sceneJointScreenDragDelta({
    required String sceneKey,
    required String bone,
    required double deltaX,
    required double deltaY,
  }) async {
    final session = _session;
    if (session == null || _error != null) return null;
    try {
      final value = await session.sceneJointScreenDragDelta(
        sceneKey: sceneKey,
        bone: bone,
        deltaXPixels: deltaX,
        deltaYPixels: deltaY,
      );
      return (x: value.x, y: value.y, z: value.z);
    } catch (error) {
      _sceneError = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> _refreshJointScreenPoints(String sceneKey) async {
    final session = _session;
    if (session == null || !_loadedSceneKeys.contains(sceneKey)) return;
    try {
      final values = await session.sceneJointScreenPositions(sceneKey: sceneKey);
      _jointScreenPointsByScene[sceneKey] = values
          .map(
            (value) => NativeJointScreenPoint(
              bone: value.bone,
              x: value.x.toDouble(),
              y: value.y.toDouble(),
              depth: value.depth.toDouble(),
              visible: value.visible,
            ),
          )
          .toList(growable: false);
    } catch (error) {
      _sceneError = error.toString();
    }
  }

  Future<void> refreshJointScreenPoints(String sceneKey) async {
    await _refreshJointScreenPoints(sceneKey);
    notifyListeners();
  }

  Future<void> removeScene(String sceneKey) async {
    _pendingScenes.remove(sceneKey);
    _loadedSceneKeys.remove(sceneKey);
    _jointNamesByScene.remove(sceneKey);
    final session = _session;
    if (session != null) {
      try {
        await session.removeScene(sceneKey: sceneKey);
        await _markTextureFrame();
      } catch (error) {
        _error = error.toString();
      }
    }
    notifyListeners();
  }

  Future<void> clearScenes() async {
    _pendingScenes.clear();
    _loadedSceneKeys.clear();
    _jointNamesByScene.clear();
    _jointScreenPointsByScene.clear();
    _sceneStatus = null;
    _sceneError = null;
    final session = _session;
    if (session != null) {
      try {
        await session.clearScenes();
        await _markTextureFrame();
      } catch (error) {
        _error = error.toString();
      }
    }
    notifyListeners();
  }

  Future<void> setSceneFkRotation({
    required String sceneKey,
    required String bone,
    required double x,
    required double y,
    required double z,
  }) async {
    final session = _session;
    if (session == null || _error != null) return;

    try {
      await session.setSceneFkRotation(
        sceneKey: sceneKey,
        bone: bone,
        x: x,
        y: y,
        z: z,
      );
      await _markTextureFrame();
      await _refreshJointScreenPoints(sceneKey);
      _sceneError = null;
    } catch (error) {
      _sceneError = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<BridgeIkResult?> setSceneTwoBoneIk({
    required String sceneKey,
    required String upper,
    required String lower,
    required String end,
    required double targetX,
    required double targetY,
    required double targetZ,
    required double poleX,
    required double poleY,
    required double poleZ,
  }) async {
    final session = _session;
    if (session == null || _error != null) return null;

    try {
      final result = await session.setSceneTwoBoneIk(
        sceneKey: sceneKey,
        upper: upper,
        lower: lower,
        end: end,
        target: BridgeVec3(x: targetX, y: targetY, z: targetZ),
        pole: BridgeVec3(x: poleX, y: poleY, z: poleZ),
      );
      await _markTextureFrame();
      await _refreshJointScreenPoints(sceneKey);
      _sceneError = null;
      notifyListeners();
      return result;
    } catch (error) {
      _sceneError = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> resetScenePose(String sceneKey) async {
    final session = _session;
    if (session == null || _error != null) return;

    try {
      await session.resetScenePose(sceneKey: sceneKey);
      await _markTextureFrame();
      await _refreshJointScreenPoints(sceneKey);
      _sceneError = null;
    } catch (error) {
      _sceneError = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setViewPreset(String preset) async {
    final session = _session;
    if (session == null || _error != null) return;

    final nativePreset = switch (preset.toLowerCase()) {
      'front' => BridgeViewPreset.front,
      'back' => BridgeViewPreset.back,
      'left' => BridgeViewPreset.left,
      'right' => BridgeViewPreset.right,
      'top' => BridgeViewPreset.top,
      'bottom' => BridgeViewPreset.bottom,
      _ => BridgeViewPreset.front,
    };

    try {
      _camera = await session.setViewPreset(preset: nativePreset);
      await _markTextureFrame();
      for (final sceneKey in _loadedSceneKeys) {
        await _refreshJointScreenPoints(sceneKey);
      }
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<void> _ensureTexture() async {
    if (!_textureBridge.supported || _textureId != null) return;
    try {
      _textureId = await _textureBridge.create();
      _textureError = null;
    } catch (error) {
      _textureError = error.toString();
    }
  }

  Future<void> _markTextureFrame() async {
    final session = _session;
    if (_textureId == null || session == null) return;
    try {
      await session.publishFrame();
      await _textureBridge.markFrame();
      _textureError = null;
    } catch (error) {
      _textureError = error.toString();
    }
  }

  int _physicalExtent(double logical, double ratio) {
    final value = (logical * ratio).round();
    return value.clamp(1, 16384).toInt();
  }

  @override
  void dispose() {
    unawaited(_textureBridge.dispose());
    _textureId = null;
    _session?.dispose();
    _session = null;
    super.dispose();
  }
}


class NativeJointScreenPoint {
  const NativeJointScreenPoint({
    required this.bone,
    required this.x,
    required this.y,
    required this.depth,
    required this.visible,
  });

  final String bone;
  final double x;
  final double y;
  final double depth;
  final bool visible;
}
