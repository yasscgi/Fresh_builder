import 'package:flutter/material.dart';

import 'native_viewport_controller.dart';

enum BuilderTool { select, move, rotate, scale }

class BuilderWorkspaceController extends ChangeNotifier {
  BuilderTool _tool = BuilderTool.select;
  bool _navigationLocked = false;
  bool _showRig = false;
  bool _busy = false;
  String? _status;
  String _viewPreset = 'front';

  BuilderTool get tool => _tool;
  bool get navigationLocked => _navigationLocked;
  bool get showRig => _showRig;
  bool get busy => _busy;
  String? get status => _status;
  String get viewPreset => _viewPreset;

  void setViewPreset(String value) {
    if (_viewPreset == value) return;
    _viewPreset = value;
    _status = '${value.toUpperCase()} view';
    notifyListeners();
  }

  void markOrbit() {
    if (_navigationLocked || _status == 'Orbit view') return;
    _status = 'Orbit view';
    notifyListeners();
  }

  void selectTool(BuilderTool value) {
    if (_tool == value) return;
    _tool = value;
    notifyListeners();
  }

  void setRigVisible(bool value) {
    if (_showRig == value) return;
    _showRig = value;
    notifyListeners();
  }


  void beginPoseGesture() {
    if (_navigationLocked) return;
    _navigationLocked = true;
    _status = 'Editing pose';
    notifyListeners();
  }

  void commitPoseGesture() {
    if (!_navigationLocked) return;
    _navigationLocked = false;
    _status = 'Pose committed';
    notifyListeners();
  }

  void cancelPoseGesture() {
    if (!_navigationLocked) return;
    _navigationLocked = false;
    _status = null;
    notifyListeners();
  }

  void setBusy(bool value, {String? status}) {
    _busy = value;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}

class BuilderToolRail extends StatelessWidget {
  const BuilderToolRail({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final BuilderWorkspaceController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _buttons(context),
          ),
        );
      },
    );
  }

  List<Widget> _buttons(BuildContext context) {
    return [
      _button(context, BuilderTool.select, Icons.ads_click_rounded, 'Select'),
      _button(context, BuilderTool.move, Icons.open_with_rounded, 'Move'),
      _button(context, BuilderTool.rotate, Icons.rotate_right_rounded, 'Rotate'),
      _button(context, BuilderTool.scale, Icons.aspect_ratio_rounded, 'Scale'),
    ];
  }

  Widget _button(
    BuildContext context,
    BuilderTool tool,
    IconData icon,
    String tooltip,
  ) {
    final active = controller.tool == tool;
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: EdgeInsets.only(bottom: tool == BuilderTool.scale ? 0 : 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(compact ? 11 : 14),
          onTap: () => controller.selectTool(tool),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: compact ? 42 : 54,
            height: compact ? 44 : 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 11 : 14),
              color: active
                  ? colors.primary
                  : colors.surfaceContainerHighest.withValues(alpha: 0.28),
              border: Border.all(
                color: active
                    ? colors.primary.withValues(alpha: 0.88)
                    : Theme.of(context).dividerColor,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.22),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: compact ? 16 : 18,
                  color: active ? Colors.white : colors.onSurfaceVariant,
                ),
                const SizedBox(height: 2),
                Text(
                  tooltip,
                  style: TextStyle(
                    fontSize: compact ? 7 : 8,
                    fontWeight: FontWeight.w800,
                    color: active ? Colors.white : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BuilderViewportStatus extends StatelessWidget {
  const BuilderViewportStatus({
    super.key,
    required this.controller,
    required this.nativeController,
    required this.assetName,
    required this.assetLoading,
    required this.cacheHit,
  });

  final BuilderWorkspaceController controller;
  final NativeViewportController nativeController;
  final String? assetName;
  final bool assetLoading;
  final bool? cacheHit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, nativeController]),
      builder: (context, _) {
        final nativeScene = nativeController.sceneStatus;
        final text = assetLoading
            ? 'Loading asset…'
            : nativeController.error != null
                ? 'Native viewport error'
                : nativeController.sceneError != null
                    ? 'Scene import error'
                    : assetName == null
                    ? nativeController.ready
                        ? 'GPU viewport ready'
                        : nativeController.initializing
                            ? 'Starting GPU viewport…'
                            : 'Select an asset'
                    : nativeScene?.loadedToGpu == true
                        ? '$assetName · GPU ready'
                        : nativeScene?.readiness == 'needs_fbx_decoder'
                            ? '$assetName · FBX decoder pending'
                            : cacheHit == true
                                ? '$assetName · cached'
                                : assetName!;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (assetLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 7),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  ),
                )
              else
                Icon(
                  controller.navigationLocked
                      ? Icons.lock_rounded
                      : nativeController.error != null
                          ? Icons.error_outline_rounded
                          : nativeController.sceneError != null
                              ? Icons.warning_amber_rounded
                              : nativeController.sceneStatus?.loadedToGpu == true
                              ? Icons.memory_rounded
                              : Icons.view_in_ar_rounded,
                  size: 15,
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
