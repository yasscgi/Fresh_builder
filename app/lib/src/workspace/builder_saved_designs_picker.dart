import 'package:flutter/material.dart';

import '../cloud/builder_design_cloud_repository.dart';

sealed class BuilderDesignRestoreChoice {
  const BuilderDesignRestoreChoice();
}

final class BuilderCloudRestoreChoice extends BuilderDesignRestoreChoice {
  const BuilderCloudRestoreChoice(this.design);
  final BuilderCloudSavedDesign design;
}

final class BuilderLocalRestoreChoice extends BuilderDesignRestoreChoice {
  const BuilderLocalRestoreChoice();
}

Future<BuilderDesignRestoreChoice?> showBuilderSavedDesignPicker({
  required BuildContext context,
  required String productId,
  BuilderDesignCloudRepository? repository,
}) async {
  final cloud = repository ?? BuilderDesignCloudRepository();

  return showModalBottomSheet<BuilderDesignRestoreChoice>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return _BuilderSavedDesignPickerSheet(
        productId: productId,
        repository: cloud,
      );
    },
  );
}

class _BuilderSavedDesignPickerSheet extends StatefulWidget {
  const _BuilderSavedDesignPickerSheet({
    required this.productId,
    required this.repository,
  });

  final String productId;
  final BuilderDesignCloudRepository repository;

  @override
  State<_BuilderSavedDesignPickerSheet> createState() =>
      _BuilderSavedDesignPickerSheetState();
}

class _BuilderSavedDesignPickerSheetState
    extends State<_BuilderSavedDesignPickerSheet> {
  late Future<List<BuilderCloudSavedDesign>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listDesigns(
      productId: widget.productId,
      limit: 30,
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = widget.repository.listDesigns(
        productId: widget.productId,
        limit: 30,
      );
    });
  }

  Future<void> _delete(BuilderCloudSavedDesign design) async {
    await widget.repository.deleteDesign(design.id);
    _refresh();
  }

  Future<void> _duplicate(BuilderCloudSavedDesign design) async {
    await widget.repository.duplicateDesign(design);
    _refresh();
  }

  Future<void> _rename(BuilderCloudSavedDesign design) async {
    final controller = TextEditingController(text: design.name);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename design'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Design name',
          ),
          onSubmitted: (value) =>
              Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (value == null || value.trim().isEmpty) return;
    await widget.repository.renameDesign(
      designId: design.id,
      name: value,
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Saved Designs',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(
                    const BuilderLocalRestoreChoice(),
                  ),
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: const Text('Local'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Expanded(
            child: FutureBuilder<List<BuilderCloudSavedDesign>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load cloud designs. You can still restore the local snapshot.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }

                final designs = snapshot.data ?? const [];
                if (designs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.repository.signedIn
                            ? 'No Native cloud designs yet.'
                            : 'Sign in to see cloud designs. Local restore is still available.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: designs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final design = designs[index];
                    final isNative =
                        design.design['format'] == 'fresh_builder_design' &&
                        (design.design['version'] as num?)?.toInt() == 5;
                    final updated = design.updatedAt?.toLocal();

                    return Material(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.36,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        enabled: isNative,
                        onTap: isNative
                            ? () => Navigator.of(context).pop(
                                  BuilderCloudRestoreChoice(design),
                                )
                            : null,
                        leading: CircleAvatar(
                          backgroundColor: isNative
                              ? colors.primary.withValues(alpha: 0.14)
                              : colors.surfaceContainerHighest,
                          child: Icon(
                            isNative
                                ? Icons.view_in_ar_rounded
                                : Icons.history_rounded,
                            color: isNative
                                ? colors.primary
                                : colors.onSurfaceVariant,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          design.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(
                          isNative
                              ? updated == null
                                  ? 'Native Design v5'
                                  : 'Native Design v5 · '
                                      '${updated.year}-'
                                      '${updated.month.toString().padLeft(2, '0')}-'
                                      '${updated.day.toString().padLeft(2, '0')} '
                                      '${updated.hour.toString().padLeft(2, '0')}:'
                                      '${updated.minute.toString().padLeft(2, '0')}'
                              : 'Legacy web Builder design',
                          style: TextStyle(
                            fontSize: 9,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Design actions',
                          onSelected: (action) {
                            switch (action) {
                              case 'rename':
                                _rename(design);
                                return;
                              case 'duplicate':
                                _duplicate(design);
                                return;
                              case 'delete':
                                _delete(design);
                                return;
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: ListTile(
                                dense: true,
                                leading: Icon(Icons.edit_rounded, size: 17),
                                title: Text('Rename'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'duplicate',
                              child: ListTile(
                                dense: true,
                                leading: Icon(Icons.copy_rounded, size: 17),
                                title: Text('Duplicate'),
                              ),
                            ),
                            PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 17,
                                ),
                                title: Text('Delete'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
