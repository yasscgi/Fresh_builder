import 'package:flutter/material.dart';

class BuilderImportCapabilities extends StatelessWidget {
  const BuilderImportCapabilities({super.key, this.compact = false});

  final bool compact;

  static const _rows = [
    (
      format: 'GLB / glTF',
      status: 'Full',
      note: 'Static + rigged characters',
      icon: Icons.check_circle_rounded,
    ),
    (
      format: 'FBX',
      status: 'Full*',
      note: 'Static + one skinned mesh/deformer',
      icon: Icons.check_circle_rounded,
    ),
    (
      format: 'STL',
      status: 'Full',
      note: 'Binary + ASCII static geometry',
      icon: Icons.check_circle_rounded,
    ),
    (
      format: '3MF',
      status: 'Export',
      note: 'Export supported; import not enabled yet',
      icon: Icons.outbox_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (compact) {
      return Tooltip(
        message: 'Import: GLB/glTF, FBX, STL · 3MF export only',
        child: Icon(
          Icons.info_outline_rounded,
          size: 17,
          color: colors.onSurfaceVariant,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Native import support',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    row.icon,
                    size: 14,
                    color: row.status.startsWith('Full')
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: 72,
                    child: Text(
                      row.format,
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 46,
                    child: Text(
                      row.status,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: row.status.startsWith('Full')
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.note,
                      style: TextStyle(
                        fontSize: 8,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '* Multi-skinned FBX is rejected explicitly until per-mesh skin palettes are implemented.',
            style: TextStyle(
              fontSize: 7.5,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
