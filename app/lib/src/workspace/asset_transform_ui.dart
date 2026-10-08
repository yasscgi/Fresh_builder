import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'builder_workspace.dart';
import 'native_viewport_controller.dart';

class AssetViewportGizmo extends StatefulWidget {
  const AssetViewportGizmo({
    required this.workspace,
    required this.viewport,
    required this.sceneKey,
    required this.onChanged,
    required this.onGestureStart,
    required this.onGestureEnd,
    required this.onGestureCancel,
  });

  final BuilderWorkspaceController workspace;
  final NativeViewportController viewport;
  final String? sceneKey;
  final ValueChanged<NativeSceneTransform> onChanged;
  final VoidCallback onGestureStart;
  final VoidCallback onGestureEnd;
  final VoidCallback onGestureCancel;

  @override
  State<AssetViewportGizmo> createState() => AssetViewportGizmoState();
}

class AssetViewportGizmoState extends State<AssetViewportGizmo> {
  NativeScreenPoint? _point;
  NativeSceneTransform? _base;
  double _dragX = 0;
  double _dragY = 0;
  double _pendingMoveX = 0;
  double _pendingMoveY = 0;
  Future<void>? _moveFlush;

  @override
  void initState() {
    super.initState();
    widget.viewport.addListener(_scheduleProjection);
    widget.workspace.addListener(_scheduleProjection);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshProjection());
  }

  @override
  void didUpdateWidget(covariant AssetViewportGizmo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewport != widget.viewport) {
      oldWidget.viewport.removeListener(_scheduleProjection);
      widget.viewport.addListener(_scheduleProjection);
    }
    if (oldWidget.workspace != widget.workspace) {
      oldWidget.workspace.removeListener(_scheduleProjection);
      widget.workspace.addListener(_scheduleProjection);
    }
    if (oldWidget.sceneKey != widget.sceneKey) {
      _point = null;
      _scheduleProjection();
    }
  }

  @override
  void dispose() {
    widget.viewport.removeListener(_scheduleProjection);
    widget.workspace.removeListener(_scheduleProjection);
    super.dispose();
  }

  void _scheduleProjection() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshProjection());
    });
  }

  Future<void> _refreshProjection() async {
    final sceneKey = widget.sceneKey;
    if (sceneKey == null || widget.workspace.tool == BuilderTool.select) {
      if (mounted && _point != null) setState(() => _point = null);
      return;
    }
    final transform = widget.viewport.sceneTransform(sceneKey);
    final point = await widget.viewport.projectWorldPoint(
      x: transform.tx,
      y: transform.ty,
      z: transform.tz,
    );
    if (!mounted || widget.sceneKey != sceneKey) return;
    setState(() => _point = point);
  }

  void _start() {
    final sceneKey = widget.sceneKey;
    if (sceneKey == null) return;
    _base = widget.viewport.sceneTransform(sceneKey);
    _dragX = 0;
    _dragY = 0;
    _pendingMoveX = 0;
    _pendingMoveY = 0;
    widget.onGestureStart();
  }

  void _update(DragUpdateDetails details, Size logicalSize) {
    final base = _base;
    final sceneKey = widget.sceneKey;
    if (base == null || sceneKey == null) return;

    _dragX += details.delta.dx;
    _dragY += details.delta.dy;

    switch (widget.workspace.tool) {
      case BuilderTool.move:
        final scaleX = widget.viewport.physicalWidth / logicalSize.width;
        final scaleY = widget.viewport.physicalHeight / logicalSize.height;
        _pendingMoveX += details.delta.dx * scaleX;
        _pendingMoveY += details.delta.dy * scaleY;
        _ensureMoveFlush();
        return;
      case BuilderTool.rotate:
        widget.onChanged(
          base.copyWith(
            rx: base.rx - _dragY * 0.012,
            ry: base.ry + _dragX * 0.012,
          ),
        );
        return;
      case BuilderTool.scale:
        final factor = math.exp(-_dragY * 0.008);
        widget.onChanged(
          base.copyWith(
            scale: (base.scale * factor).clamp(0.05, 8.0).toDouble(),
          ),
        );
        return;
      case BuilderTool.select:
        return;
    }
  }

  void _ensureMoveFlush() {
    if (_moveFlush != null ||
        (_pendingMoveX.abs() < 0.001 && _pendingMoveY.abs() < 0.001)) {
      return;
    }
    final future = _flushMove();
    _moveFlush = future;
    unawaited(
      future.whenComplete(() {
        _moveFlush = null;
        if (_pendingMoveX.abs() >= 0.001 || _pendingMoveY.abs() >= 0.001) {
          _ensureMoveFlush();
        }
      }),
    );
  }

  Future<void> _flushPendingMove() async {
    while (_moveFlush != null ||
        _pendingMoveX.abs() >= 0.001 ||
        _pendingMoveY.abs() >= 0.001) {
      _ensureMoveFlush();
      final active = _moveFlush;
      if (active != null) {
        await active;
      } else {
        break;
      }
    }
  }

  Future<void> _flushMove() async {
    final sceneKey = widget.sceneKey;
    if (sceneKey == null) return;
    final current = widget.viewport.sceneTransform(sceneKey);
    final dx = _pendingMoveX;
    final dy = _pendingMoveY;
    _pendingMoveX = 0;
    _pendingMoveY = 0;

    final delta = await widget.viewport.screenDragWorldDeltaAt(
      x: current.tx,
      y: current.ty,
      z: current.tz,
      deltaX: dx,
      deltaY: dy,
    );
    if (delta == null || widget.sceneKey != sceneKey) return;

    widget.onChanged(
      current.copyWith(
        tx: current.tx + delta.x,
        ty: current.ty + delta.y,
        tz: current.tz + delta.z,
      ),
    );
  }

  Future<void> _finish() async {
    await _flushPendingMove();
    _base = null;
    widget.onGestureEnd();
    await _refreshProjection();
  }

  Future<void> _cancel() async {
    _pendingMoveX = 0;
    _pendingMoveY = 0;
    await _moveFlush;
    _base = null;
    widget.onGestureCancel();
    await _refreshProjection();
  }

  @override
  Widget build(BuildContext context) {
    final point = _point;
    final sceneKey = widget.sceneKey;
    final tool = widget.workspace.tool;
    if (sceneKey == null ||
        point == null ||
        !point.visible ||
        tool == BuilderTool.select ||
        widget.viewport.physicalWidth <= 0 ||
        widget.viewport.physicalHeight <= 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final x =
            point.x * constraints.maxWidth / widget.viewport.physicalWidth;
        final y =
            point.y * constraints.maxHeight / widget.viewport.physicalHeight;
        final colors = Theme.of(context).colorScheme;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: x - 32,
              top: y - 32,
              width: 64,
              height: 64,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => _start(),
                onPanUpdate: (details) => _update(
                  details,
                  Size(constraints.maxWidth, constraints.maxHeight),
                ),
                onPanEnd: (_) => unawaited(_finish()),
                onPanCancel: () => unawaited(_cancel()),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surface.withValues(alpha: 0.12),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.85),
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.18),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: Icon(
                    switch (tool) {
                      BuilderTool.move => Icons.open_with_rounded,
                      BuilderTool.rotate => Icons.rotate_right_rounded,
                      BuilderTool.scale => Icons.aspect_ratio_rounded,
                      _ => Icons.ads_click_rounded,
                    },
                    color: colors.primary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class AssetTransformPanel extends StatelessWidget {
  const AssetTransformPanel({
    required this.workspace,
    required this.viewport,
    required this.sceneKey,
    required this.onChanged,
    required this.onGestureStart,
    required this.onGestureEnd,
    required this.onGestureCancel,
    required this.onUndo,
    required this.onRedo,
    required this.compact,
  });

  final BuilderWorkspaceController workspace;
  final NativeViewportController viewport;
  final String? sceneKey;
  final ValueChanged<NativeSceneTransform> onChanged;
  final VoidCallback onGestureStart;
  final VoidCallback onGestureEnd;
  final VoidCallback onGestureCancel;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([workspace, viewport]),
      builder: (context, _) {
        final key = sceneKey;
        final tool = workspace.tool;
        if (key == null || tool == BuilderTool.select) {
          return const SizedBox.shrink();
        }

        final transform = viewport.sceneTransform(key);
        final colors = Theme.of(context).colorScheme;
        final width = compact ? 210.0 : 250.0;

        return Container(
          width: width,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              switch (tool) {
            BuilderTool.move => _TransformAxes(
                title: 'Move asset',
                values: [transform.tx, transform.ty, transform.tz],
                min: -0.25,
                max: 0.25,
                onStart: onGestureStart,
                onEnd: onGestureEnd,
                formatter: (value) => '${(value * 1000).round()} mm',
                onChanged: (axis, value) {
                  onChanged(
                    transform.copyWith(
                      tx: axis == 0 ? value : transform.tx,
                      ty: axis == 1 ? value : transform.ty,
                      tz: axis == 2 ? value : transform.tz,
                    ),
                  );
                },
              ),
            BuilderTool.rotate => _TransformAxes(
                title: 'Rotate asset',
                values: [transform.rx, transform.ry, transform.rz],
                min: -math.pi,
                max: math.pi,
                onStart: onGestureStart,
                onEnd: onGestureEnd,
                formatter: (value) =>
                    '${(value * 180 / math.pi).round()}°',
                onChanged: (axis, value) {
                  onChanged(
                    transform.copyWith(
                      rx: axis == 0 ? value : transform.rx,
                      ry: axis == 1 ? value : transform.ry,
                      rz: axis == 2 ? value : transform.rz,
                    ),
                  );
                },
              ),
            BuilderTool.scale => _TransformScale(
                value: transform.scale,
                onStart: onGestureStart,
                onEnd: onGestureEnd,
                onChanged: (value) =>
                    onChanged(transform.copyWith(scale: value)),
              ),
            _ => const SizedBox.shrink(),
              },
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Undo transform',
                    onPressed: viewport.canUndoSceneTransform(key) ? onUndo : null,
                    icon: const Icon(Icons.undo_rounded, size: 16),
                  ),
                  IconButton(
                    tooltip: 'Redo transform',
                    onPressed: viewport.canRedoSceneTransform(key) ? onRedo : null,
                    icon: const Icon(Icons.redo_rounded, size: 16),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      onGestureStart();
                      onChanged(const NativeSceneTransform());
                      onGestureEnd();
                    },
                    icon: const Icon(Icons.restart_alt_rounded, size: 14),
                    label: const Text('Reset'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TransformAxes extends StatelessWidget {
  const _TransformAxes({
    required this.title,
    required this.values,
    required this.min,
    required this.max,
    required this.formatter,
    required this.onStart,
    required this.onEnd,
    required this.onChanged,
  });

  final String title;
  final List<double> values;
  final double min;
  final double max;
  final String Function(double value) formatter;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final void Function(int axis, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        for (var axis = 0; axis < 3; axis++)
          Row(
            children: [
              SizedBox(
                width: 14,
                child: Text(
                  const ['X', 'Y', 'Z'][axis],
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: Slider(
                  min: min,
                  max: max,
                  value: values[axis].clamp(min, max).toDouble(),
                  onChangeStart: (_) => onStart(),
                  onChanged: (value) => onChanged(axis, value),
                  onChangeEnd: (_) => onEnd(),
                ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  formatter(values[axis]),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _TransformScale extends StatelessWidget {
  const _TransformScale({
    required this.value,
    required this.onStart,
    required this.onEnd,
    required this.onChanged,
  });

  final double value;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Scale asset',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                min: 0.25,
                max: 3.0,
                value: value.clamp(0.25, 3.0).toDouble(),
                onChangeStart: (_) => onStart(),
                onChanged: onChanged,
                onChangeEnd: (_) => onEnd(),
              ),
            ),
            SizedBox(
              width: 46,
              child: Text(
                '${value.toStringAsFixed(2)}×',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

