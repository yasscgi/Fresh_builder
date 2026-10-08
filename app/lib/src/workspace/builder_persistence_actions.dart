import 'package:flutter/material.dart';

class BuilderPersistenceActions extends StatelessWidget {
  const BuilderPersistenceActions({
    super.key,
    required this.onSave,
    required this.onRestore,
    required this.onValidate,
    required this.onExportStl,
    required this.onExport3mf,
    this.compact = false,
  });

  final VoidCallback onSave;
  final VoidCallback onRestore;
  final VoidCallback onValidate;
  final VoidCallback onExportStl;
  final VoidCallback onExport3mf;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final buttons = <({IconData icon, String tooltip, VoidCallback action})>[
      (icon: Icons.save_rounded, tooltip: 'Save Design', action: onSave),
      (icon: Icons.restore_rounded, tooltip: 'Restore Design', action: onRestore),
      (icon: Icons.fact_check_outlined, tooltip: 'Validate Print', action: onValidate),
      (icon: Icons.print_rounded, tooltip: 'Export STL', action: onExportStl),
      (icon: Icons.inventory_2_outlined, tooltip: 'Export 3MF', action: onExport3mf),
    ];

    if (compact) {
      return Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final button in buttons)
                IconButton(
                  tooltip: button.tooltip,
                  onPressed: button.action,
                  icon: Icon(button.icon, size: 17),
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final button in buttons)
          OutlinedButton.icon(
            onPressed: button.action,
            icon: Icon(button.icon, size: 16),
            label: Text(button.tooltip),
          ),
      ],
    );
  }
}
