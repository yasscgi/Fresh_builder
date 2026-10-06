import 'package:flutter/foundation.dart';

import 'builder_asset_cache.dart';
import 'builder_repository.dart';

class BuilderRuntime extends ChangeNotifier {
  BuilderRuntime(
    this._repository, {
    BuilderAssetCache? assetCache,
  }) : _assetCache = assetCache ?? BuilderAssetCache();

  final BuilderRepository _repository;
  final BuilderAssetCache _assetCache;

  bool loading = false;
  String? error;
  BuilderProductBundle? bundle;

  String? selectedAssetId;
  String? selectedVariationId;
  LocalBuilderAsset? localAsset;
  bool assetLoading = false;
  String? assetError;

  Future<void> load({String? productId}) async {
    if (loading) return;

    loading = true;
    error = null;
    notifyListeners();

    try {
      final resolvedId = productId ?? await _resolveFirstProduct();
      bundle = await _repository.loadProduct(resolvedId);
      await _preloadDefaults();
    } catch (exception) {
      error = exception.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectAsset(
    BuilderAssetRecord asset, {
    String? variationId,
  }) async {
    final nextVariationId = variationId ??
        (asset.variations.isEmpty ? null : asset.variations.first.id);

    if (asset.id == selectedAssetId &&
        nextVariationId == selectedVariationId &&
        localAsset != null) {
      return;
    }

    selectedAssetId = asset.id;
    selectedVariationId = nextVariationId;
    assetLoading = true;
    assetError = null;
    notifyListeners();

    try {
      final resolved = await _repository.resolveAsset(
        asset,
        variationId: nextVariationId,
      );
      localAsset = await _assetCache.getOrDownload(resolved);
    } catch (exception) {
      assetError = exception.toString();
    } finally {
      assetLoading = false;
      notifyListeners();
    }
  }

  List<BuilderAssetRecord> assetsForCategory(String categorySlug) {
    final current = bundle;
    if (current == null) return const [];
    return current.assets
        .where((asset) => asset.categorySlug == categorySlug)
        .toList(growable: false);
  }

  Future<void> _preloadDefaults() async {
    final current = bundle;
    if (current == null) return;

    BuilderAssetRecord? base;
    BuilderAssetRecord? rig;

    for (final asset in current.assets) {
      if (base == null && asset.isBaseCharacter) base = asset;
      if (rig == null && asset.isRig) rig = asset;
    }

    // The base character is the first visible geometry needed by the viewport.
    // Rig data will be loaded by the rig importer after the model path is wired
    // into Rust; do not download both large files concurrently on mobile.
    if (base != null) {
      await selectAsset(base);
    } else if (rig != null) {
      await selectAsset(rig);
    }
  }

  Future<String> _resolveFirstProduct() async {
    final ids = await _repository.listBuilderProductIds();
    if (ids.isEmpty) {
      throw StateError('No Builder-enabled product is available.');
    }
    return ids.first;
  }

  @override
  void dispose() {
    _assetCache.dispose();
    super.dispose();
  }
}
