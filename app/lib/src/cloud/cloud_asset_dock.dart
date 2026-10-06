import 'package:flutter/material.dart';

import 'builder_asset_url_resolver.dart';
import 'builder_cloud_models.dart';
import 'supabase_bootstrap.dart';

class CloudAssetDock extends StatefulWidget {
  const CloudAssetDock({
    super.key,
    required this.assets,
    required this.selectedAssetId,
    required this.onSelected,
  });

  final List<BuilderCloudAsset> assets;
  final String? selectedAssetId;
  final ValueChanged<BuilderCloudAsset> onSelected;

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

    return Container(
      height: 112,
      padding: const EdgeInsets.all(7),
      decoration: _decoration(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.assets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final asset = widget.assets[index];
          return _AssetCard(
            asset: asset,
            selected: widget.selectedAssetId == asset.id,
            resolver: _resolver,
            onTap: () => widget.onSelected(asset),
          );
        },
      ),
    );
  }

  BoxDecoration _decoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).dividerColor),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.asset,
    required this.selected,
    required this.resolver,
    required this.onTap,
  });

  final BuilderCloudAsset asset;
  final bool selected;
  final BuilderAssetUrlResolver? resolver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: 92,
      child: Material(
        color: selected
            ? colors.primary.withValues(alpha: 0.16)
            : colors.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.all(5),
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
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (asset.variations.isNotEmpty)
                  Text(
                    '${asset.variations.length} variations',
                    style: TextStyle(
                      fontSize: 8,
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
    if (asset.thumbnailRef == null || resolver == null) {
      return _fallback(context);
    }

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
      future: resolver.resolve(assetId: asset.id, kind: 'thumbnail'),
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
