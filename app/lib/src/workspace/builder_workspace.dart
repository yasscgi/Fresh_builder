import 'package:flutter/material.dart';

enum BuilderTool { select, move, rotate, scale }

class BuilderWorkspaceController extends ChangeNotifier {
  BuilderTool _tool = BuilderTool.select;
  bool _navigationLocked = false;
  bool _showRig = false;
  bool _handOpen = true;
  bool _busy = false;
  String? _status;

  BuilderTool get tool => _tool;
  bool get navigationLocked => _navigationLocked;
  bool get showRig => _showRig;
  bool get handOpen => _handOpen;
  bool get busy => _busy;
  String? get status => _status;

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

  void toggleHand() {
    _handOpen = !_handOpen;
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
          child: compact
              ? Row(mainAxisSize: MainAxisSize.min, children: _buttons(context))
              : Column(mainAxisSize: MainAxisSize.min, children: _buttons(context)),
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
      child: IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: () => controller.selectTool(tool),
        icon: Icon(icon, size: 19),
        style: IconButton.styleFrom(
          foregroundColor: active ? colors.primary : colors.onSurfaceVariant,
          backgroundColor:
              active ? colors.primary.withValues(alpha: 0.16) : Colors.transparent,
        ),
      ),
    );
  }
}

class BuilderViewportStatus extends StatelessWidget {
  const BuilderViewportStatus({
    super.key,
    required this.controller,
    required this.assetName,
    required this.assetLoading,
    required this.cacheHit,
  });

  final BuilderWorkspaceController controller;
  final String? assetName;
  final bool assetLoading;
  final bool? cacheHit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final text = assetLoading
            ? 'Loading asset…'
            : assetName == null
                ? 'Select an asset'
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
