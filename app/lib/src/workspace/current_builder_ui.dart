import 'package:flutter/material.dart';

class CurrentBuilderCategoryRail extends StatelessWidget {
  const CurrentBuilderCategoryRail({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<(IconData, String)> categories;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 88,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.985),
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 34,
            offset: const Offset(10, 0),
          ),
        ],
      ),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final active = index == selected;
          final item = categories[index];
          return Tooltip(
            message: item.$2,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onSelect(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                decoration: BoxDecoration(
                  gradient: active
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colors.primary.withValues(alpha: 0.92),
                            colors.primary,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active
                        ? colors.primary.withValues(alpha: 0.82)
                        : Colors.transparent,
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.26),
                            blurRadius: 20,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.$1,
                      size: 22,
                      color: active ? Colors.white : colors.onSurfaceVariant,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: active ? Colors.white : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class CurrentBuilderMobileCategoryNav extends StatelessWidget {
  const CurrentBuilderMobileCategoryNav({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<(IconData, String)> categories;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 26,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final active = index == selected;
          final item = categories[index];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 62,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              decoration: BoxDecoration(
                gradient: active
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.primary.withValues(alpha: 0.94),
                          colors.primary,
                        ],
                      )
                    : null,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active
                      ? colors.primary.withValues(alpha: 0.75)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.$1,
                    size: 21,
                    color: active ? Colors.white : colors.onSurfaceVariant,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class CurrentBuilderRigRail extends StatelessWidget {
  const CurrentBuilderRigRail({
    super.key,
    required this.ikActive,
    required this.fkActive,
    required this.handOpen,
    required this.onIk,
    required this.onFk,
    required this.onOpenHand,
    required this.onCloseHand,
    this.tablet = false,
  });

  final bool ikActive;
  final bool fkActive;
  final bool handOpen;
  final VoidCallback onIk;
  final VoidCallback onFk;
  final VoidCallback onOpenHand;
  final VoidCallback onCloseHand;
  final bool tablet;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tablet ? 62 : 50,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(context, 'IK', Icons.accessibility_new_rounded, ikActive, onIk),
          const SizedBox(height: 7),
          _button(context, 'FK', Icons.account_tree_outlined, fkActive, onFk),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Divider(height: 1, color: Theme.of(context).dividerColor),
          ),
          _button(context, 'Open', Icons.pan_tool_alt_rounded, handOpen, onOpenHand),
          const SizedBox(height: 7),
          _button(context, 'Close', Icons.back_hand_outlined, !handOpen, onCloseHand),
        ],
      ),
    );
  }

  Widget _button(
    BuildContext context,
    String label,
    IconData icon,
    bool active,
    VoidCallback onTap,
  ) {
    final colors = Theme.of(context).colorScheme;
    final h = tablet ? 52.0 : 46.0;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        height: h,
        decoration: BoxDecoration(
          gradient: active
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.primary.withValues(alpha: 0.92), colors.primary],
                )
              : null,
          color: active ? null : colors.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: active
                ? colors.primary.withValues(alpha: 0.8)
                : Theme.of(context).dividerColor,
          ),
          boxShadow: [
            BoxShadow(
              color: active
                  ? colors.primary.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: active ? 18 : 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: tablet ? 18 : 16, color: active ? Colors.white : colors.onSurfaceVariant),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: tablet ? 9 : 8,
                fontWeight: FontWeight.w900,
                color: active ? Colors.white : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum CurrentBuilderViewPreset { front, back, left, right, top, bottom }

class CurrentBuilderViewControls extends StatefulWidget {
  const CurrentBuilderViewControls({
    super.key,
    required this.onView,
    this.onOrbit,
    this.disabled = false,
  });

  final ValueChanged<CurrentBuilderViewPreset> onView;
  final void Function(double dx, double dy)? onOrbit;
  final bool disabled;

  @override
  State<CurrentBuilderViewControls> createState() => _CurrentBuilderViewControlsState();
}

class _CurrentBuilderViewControlsState extends State<CurrentBuilderViewControls> {
  Offset? _last;
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: widget.disabled,
      child: AnimatedOpacity(
        opacity: widget.disabled ? 0.45 : 1,
        duration: const Duration(milliseconds: 120),
        child: SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onPanStart: (details) {
                  _last = details.localPosition;
                  _dragDistance = 0;
                },
                onPanUpdate: (details) {
                  final previous = _last;
                  if (previous == null) return;
                  final delta = details.localPosition - previous;
                  _last = details.localPosition;
                  _dragDistance += delta.distance;
                  widget.onOrbit?.call(delta.dx, delta.dy);
                },
                onPanEnd: (_) => _last = null,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.primary.withValues(alpha: 0.26)),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.10),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: -0.14,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.14),
                            border: Border.all(color: colors.primary.withValues(alpha: 0.42)),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                      _face(context, 'TOP', Alignment.topCenter, CurrentBuilderViewPreset.top),
                      _face(context, 'FRONT', Alignment.bottomCenter, CurrentBuilderViewPreset.front),
                    ],
                  ),
                ),
              ),
              Positioned(top: 0, child: _arrow(context, Icons.keyboard_arrow_up_rounded, CurrentBuilderViewPreset.top)),
              Positioned(bottom: 0, child: _arrow(context, Icons.keyboard_arrow_down_rounded, CurrentBuilderViewPreset.bottom)),
              Positioned(left: 0, child: _arrow(context, Icons.keyboard_arrow_left_rounded, CurrentBuilderViewPreset.left)),
              Positioned(right: 0, child: _arrow(context, Icons.keyboard_arrow_right_rounded, CurrentBuilderViewPreset.right)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _face(
    BuildContext context,
    String label,
    Alignment alignment,
    CurrentBuilderViewPreset preset,
  ) {
    return Align(
      alignment: alignment,
      child: InkWell(
        onTap: () {
          if (_dragDistance <= 5) widget.onView(preset);
          _dragDistance = 0;
        },
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 6.5,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _arrow(
    BuildContext context,
    IconData icon,
    CurrentBuilderViewPreset preset,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: () => widget.onView(preset),
      child: SizedBox(
        width: 20,
        height: 20,
        child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
