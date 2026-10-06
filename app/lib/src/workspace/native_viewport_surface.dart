import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'builder_workspace.dart';
import 'native_viewport_controller.dart';

class NativeViewportSurface extends StatefulWidget {
  const NativeViewportSurface({
    super.key,
    required this.nativeController,
    required this.workspaceController,
    required this.child,
    required this.allowDirectOrbit,
  });

  final NativeViewportController nativeController;
  final BuilderWorkspaceController workspaceController;
  final Widget child;
  final bool allowDirectOrbit;

  @override
  State<NativeViewportSurface> createState() => _NativeViewportSurfaceState();
}

class _NativeViewportSurfaceState extends State<NativeViewportSurface> {
  Size? _lastSize;
  double? _lastScale;
  Offset? _lastFocalPoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 1,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 1,
        );
        _scheduleNativeExtent(size);

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent ||
                widget.workspaceController.navigationLocked) {
              return;
            }
            final normalized = event.scrollDelta.dy / 240.0;
            widget.nativeController.zoom(
              normalized,
              sensitivity: 0.12,
            );
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: widget.workspaceController.navigationLocked
                ? null
                : (details) {
                    _lastScale = 1;
                    _lastFocalPoint = details.localFocalPoint;
                  },
            onScaleUpdate: widget.workspaceController.navigationLocked
                ? null
                : (details) {
                    final previousScale = _lastScale ?? 1;
                    final ratio = previousScale == 0
                        ? 1.0
                        : details.scale / previousScale;
                    _lastScale = details.scale;

                    if ((ratio - 1).abs() > 0.002) {
                      final delta = -math.log(ratio) * 5;
                      widget.nativeController.zoom(
                        delta,
                        sensitivity: 0.2,
                      );
                    }

                    final previousPoint =
                        _lastFocalPoint ?? details.localFocalPoint;
                    final delta =
                        details.localFocalPoint - previousPoint;
                    _lastFocalPoint = details.localFocalPoint;

                    if (widget.allowDirectOrbit &&
                        details.pointerCount == 1 &&
                        delta.distanceSquared > 0.01) {
                      widget.nativeController.orbit(
                        delta.dx,
                        delta.dy,
                      );
                      widget.workspaceController.markOrbit();
                    }
                  },
            onScaleEnd: (_) {
              _lastScale = null;
              _lastFocalPoint = null;
            },
            child: widget.child,
          ),
        );
      },
    );
  }

  void _scheduleNativeExtent(Size size) {
    if (size.width <= 0 || size.height <= 0 || size == _lastSize) return;
    _lastSize = size;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ratio = MediaQuery.devicePixelRatioOf(context);
      widget.nativeController.ensureInitialized(
        logicalWidth: size.width,
        logicalHeight: size.height,
        devicePixelRatio: ratio,
      );
    });
  }
}
