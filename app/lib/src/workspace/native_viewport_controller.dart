import 'dart:async';

import 'package:flutter/foundation.dart';

import '../rust/api/builder.dart';

class NativeViewportController extends ChangeNotifier {
  NativeViewportSession? _session;
  BridgeCameraState? _camera;
  NativeSceneStatus? _sceneStatus;
  String? _error;
  String? _pendingScenePath;
  double _pendingMetersPerUnit = 1;
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
      await session.renderClear(
        color: const BridgeColor(
          r: 0.035,
          g: 0.043,
          b: 0.098,
          a: 1,
        ),
      );
      await _loadPendingScene();
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

  Future<void> loadLocalScene({
    required String path,
    required double metersPerUnit,
  }) async {
    _pendingScenePath = path;
    _pendingMetersPerUnit =
        metersPerUnit.isFinite && metersPerUnit > 0 ? metersPerUnit : 1;

    if (_session == null) {
      notifyListeners();
      return;
    }
    await _loadPendingScene();
  }

  Future<void> _loadPendingScene() async {
    final session = _session;
    final path = _pendingScenePath;
    if (session == null || path == null || path.isEmpty) return;

    try {
      _sceneStatus = await session.loadLocalScene(
        path: path,
        metersPerUnit: _pendingMetersPerUnit,
      );
      _error = null;
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  Future<void> clearScene() async {
    _pendingScenePath = null;
    _sceneStatus = null;
    final session = _session;
    if (session != null) {
      try {
        await session.clearScene();
      } catch (error) {
        _error = error.toString();
      }
    }
    notifyListeners();
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
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      notifyListeners();
    }
  }

  int _physicalExtent(double logical, double ratio) {
    final value = (logical * ratio).round();
    return value.clamp(1, 16384);
  }

  @override
  void dispose() {
    _session?.dispose();
    _session = null;
    super.dispose();
  }
}
