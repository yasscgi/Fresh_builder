import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'builder_asset_url_resolver.dart';
import 'builder_cloud_models.dart';
import 'supabase_bootstrap.dart';

class CloudAssetDock extends StatefulWidget {
  const CloudAssetDock({
    super.key,
    required this.assets,
    required this.selectedSelectionKey,
    required this.onSelected,
    this.compact = false,
    this.title,
  });

  final List<BuilderCloudAsset> assets;
  final String? selectedSelectionKey;
  final ValueChanged<BuilderAssetChoice> onSelected;
  final bool compact;
  final String? title;

  @override
  State<CloudAssetDock> createState() => _CloudAssetDockState();
}

class _CloudAssetDockState extends State<CloudAssetDock> {
  BuilderAssetUrlResolver? _resolver;

  @override
  void initState() {
    super.initState();
    if (FreshSupabaseBootstrap.isInitialized) {
      _resolver = BuilderAssetUrlResolver();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FreshSupabaseBootstrap.client?.auth.onAuthStateChange;
    if (stream == null) return _buildDock(context);

    return StreamBuilder<AuthState>(
      stream: stream,
      builder: (context, _) => _buildDock(context),
    );
  }

  Widget _buildDock(BuildContext context) {
    if (widget.assets.isEmpty) {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        decoration: _decoration(context),
        child: Text(
          'No assets in this category',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final colors = Theme.of(context).colorScheme;
    return Container(
      height: widget.compact ? 108 : 150,
      decoration: _decoration(context),
      child: Column(
        children: [
          SizedBox(
            height: widget.compact ? 30 : 44,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 9 : 12,
              ),
              child: Row(
                children: [
                  Text(
                    widget.title ?? 'Assets',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.compact ? 9 : 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.compact ? 6 : 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.assets.length}',
                      style: TextStyle(
                        fontSize: widget.compact ? 7 : 8,
                        fontWeight: FontWeight.w900,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  if (!widget.compact) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.grid_view_rounded,
                      size: 14,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(widget.compact ? 5 : 8),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.assets.length,
                separatorBuilder: (_, __) =>
                    SizedBox(width: widget.compact ? 5 : 7),
                itemBuilder: (context, index) {
                  final asset = widget.assets[index];
                  final selected = widget.selectedSelectionKey == asset.id ||
                      widget.selectedSelectionKey
                              ?.startsWith('${asset.id}|') ==
                          true;

                  return _AssetCard(
                    asset: asset,
                    selected: selected,
                    resolver: _resolver,
                    compact: widget.compact,
                    onTap: () => _selectAsset(context, asset),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectAsset(
    BuildContext context,
    BuilderCloudAsset asset,
  ) async {
    if (asset.variations.length <= 1) {
      widget.onSelected(
        BuilderAssetChoice(
          asset: asset,
          variation: asset.variations.isEmpty ? null : asset.variations.first,
        ),
      );
      return;
    }

    final choice = await showModalBottomSheet<BuilderCloudVariation>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: Text(
                  asset.name,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final variation in asset.variations)
                ListTile(
                  leading: const Icon(Icons.view_in_ar_outlined),
                  title: Text(variation.name),
                  onTap: () => Navigator.pop(sheetContext, variation),
                ),
            ],
          ),
        );
      },
    );

    if (choice != null) {
      widget.onSelected(BuilderAssetChoice(asset: asset, variation: choice));
    }
  }

  BoxDecoration _decoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).dividerColor),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.09),
          blurRadius: 28,
          offset: const Offset(0, -6),
        ),
      ],
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.asset,
    required this.selected,
    required this.resolver,
    required this.onTap,
    required this.compact,
  });

  final BuilderCloudAsset asset;
  final bool selected;
  final BuilderAssetUrlResolver? resolver;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: compact ? 64 : 86,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.16)
            : colors.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: EdgeInsets.all(compact ? 3 : 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? colors.primary.withValues(alpha: 0.65)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              children: [
                Expanded(child: _thumbnail(context)),
                const SizedBox(height: 4),
                Text(
                  asset.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 7 : 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (asset.variations.isNotEmpty)
                  Text(
                    '${asset.variations.length}',
                    style: TextStyle(
                      fontSize: compact ? 7 : 8,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumbnail(BuildContext context) {
    final resolver = this.resolver;
    if (resolver == null) return _fallback(context);

    final variationId = asset.thumbnailRef == null &&
            asset.variations.isNotEmpty &&
            asset.variations.first.thumbnailRef != null
        ? asset.variations.first.id
        : null;

    final hasThumbnail = asset.thumbnailRef != null ||
        (variationId != null &&
            asset.variations.first.thumbnailRef != null);

    if (!hasThumbnail) return _fallback(context);

    if (FreshSupabaseBootstrap.client?.auth.currentSession == null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          _fallback(context),
          const Icon(Icons.lock_outline_rounded, size: 18),
        ],
      );
    }

    return FutureBuilder<BuilderAssetUrl>(
      future: resolver.resolve(
        assetId: asset.id,
        kind: 'thumbnail',
        variationId: variationId,
      ),
      builder: (context, snapshot) {
        final url = snapshot.data?.uri.toString();
        if (url == null) {
          if (snapshot.hasError) return _fallback(context);
          return const Center(
            child: SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => _fallback(context),
          ),
        );
      },
    );
  }

  Widget _fallback(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        asset.role == 'stand'
            ? Icons.layers_rounded
            : asset.type == 'pose'
                ? Icons.accessibility_new_rounded
                : Icons.view_in_ar_rounded,
        size: 25,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
