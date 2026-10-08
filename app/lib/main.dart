import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fresh_builder_viewport_texture/fresh_builder_viewport_texture.dart';

import 'src/cloud/builder_asset_disk_cache.dart';
import 'src/cloud/builder_cloud_models.dart';
import 'src/cloud/builder_cloud_repository.dart';
import 'src/cloud/builder_product_repository.dart';
import 'src/cloud/cloud_account_button.dart';
import 'src/cloud/cloud_asset_dock.dart';
import 'src/cloud/cloud_product_picker_button.dart';
import 'src/cloud/supabase_bootstrap.dart';
import 'src/rust/api/rig.dart';
import 'src/rust/frb_generated.dart';
import 'src/workspace/builder_workspace.dart';
import 'src/workspace/current_builder_ui.dart';
import 'src/workspace/native_rig_controller.dart';
import 'src/workspace/native_viewport_controller.dart';
import 'src/workspace/native_viewport_surface.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FreshBuilderRust.init();
  final cloudReady = await FreshSupabaseBootstrap.initialize();
  runApp(FreshBuilderApp(cloudReady: cloudReady));
}

class FreshBuilderApp extends StatefulWidget {
  const FreshBuilderApp({super.key, required this.cloudReady});

  final bool cloudReady;

  @override
  State<FreshBuilderApp> createState() => _FreshBuilderAppState();
}

class _FreshBuilderAppState extends State<FreshBuilderApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C3AED),
      brightness: brightness,
      surface: dark ? const Color(0xFF111427) : const Color(0xFFFFFFFF),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF090B19) : const Color(0xFFF7F7FB),
      dividerColor: dark
          ? const Color(0xFF8B5CF6).withValues(alpha: 0.18)
          : const Color(0xFF7C3AED).withValues(alpha: 0.12),
    );
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fresh Builder',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _themeMode,
      home: BuilderPage(
        cloudReady: widget.cloudReady,
        onToggleTheme: () => setState(() {
          _themeMode =
              _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
        }),
      ),
    );
  }
}

class BuilderPage extends StatefulWidget {
  const BuilderPage({
    super.key,
    required this.onToggleTheme,
    required this.cloudReady,
  });

  final VoidCallback onToggleTheme;
  final bool cloudReady;

  @override
  State<BuilderPage> createState() => _BuilderPageState();
}

class _BuilderPageState extends State<BuilderPage> {
  static const _baseCharacterSceneKey = 'role:base_character';
  int _selectedCategory = 0;
  BuilderProductSummary? _selectedProduct;
  BuilderCloudData? _cloudData;
  BuilderAssetChoice? _selectedAsset;
  CachedBuilderAsset? _cachedAsset;
  BuilderAssetDiskCache? _assetCache;
  bool _cloudLoading = false;
  bool _assetLoading = false;
  String? _cloudError;
  String? _assetError;
  late final BuilderWorkspaceController _workspace;
  late final NativeRigController _nativeRig;
  late final NativeViewportController _nativeViewport;

  static const fallbackCategories = <(IconData, String)>[
    (Icons.accessibility_new_rounded, 'Pose'),
    (Icons.checkroom_rounded, 'Hat'),
    (Icons.shield_outlined, 'Back'),
    (Icons.sports_martial_arts_rounded, 'Hand'),
    (Icons.layers_rounded, 'Base'),
  ];

  @override
  void initState() {
    super.initState();
    _workspace = BuilderWorkspaceController();
    _nativeRig = NativeRigController();
    _nativeViewport = NativeViewportController();
    unawaited(_nativeRig.ensureInitialized());
    if (widget.cloudReady) {
      _assetCache = BuilderAssetDiskCache();
    }
  }

  Future<void> _preloadBaseCharacter(BuilderCloudData data) async {
    final cache = _assetCache;
    if (cache == null) return;

    BuilderCloudAsset? base;
    for (final asset in data.assets) {
      final role = asset.role.trim().toLowerCase();
      if (role == 'base_character' || asset.type == 'base_character') {
        base = asset;
        break;
      }
    }
    if (base == null) return;

    final choice = BuilderAssetChoice(
      asset: base,
      variation: base.variations.isEmpty ? null : base.variations.first,
    );

    try {
      _workspace.setBusy(true, status: 'Loading base character');
      final local = await cache.getOrDownload(choice);
      await _nativeViewport.upsertLocalScene(
        sceneKey: _baseCharacterSceneKey,
        path: local.file.path,
        metersPerUnit: _metersPerUnit(choice),
      );
      if (!mounted) return;
      final nativeScene = _nativeViewport.sceneStatus;
      _workspace.setBusy(
        false,
        status: nativeScene?.loadedToGpu == true
            ? 'Base character GPU ready'
            : nativeScene?.readiness == 'needs_fbx_decoder'
                ? 'Base character cached · FBX decoder pending'
                : 'Base character ready',
      );
    } catch (error) {
      if (!mounted) return;
      _workspace.setBusy(false, status: 'Base character load failed');
    }
  }


  Future<void> _setRigMode(BridgeRigMode mode) async {
    await _nativeRig.setMode(mode);
    if (!mounted) return;
    _workspace.setRigVisible(_nativeRig.mode != BridgeRigMode.none);
  }

  Future<void> _setHandOpen(bool open) async {
    await _nativeRig.setHandOpen(open);
  }

  Future<void> _selectFkBone(String? bone) async {
    await _nativeRig.selectBone(bone);
  }

  Future<void> _beginFkGesture() async {
    if (!_nativeViewport.hasLoadedScene(_baseCharacterSceneKey)) return;
    _workspace.beginPoseGesture();
    await _nativeRig.beginGesture();
  }

  void _updateFkAxis(String axis, double value) {
    final bone = _nativeRig.selectedBone;
    if (bone == null || !_nativeViewport.hasLoadedScene(_baseCharacterSceneKey)) return;
    final current = _nativeRig.selectedFkRotation;
    _nativeRig.updateFkRotation(
      viewport: _nativeViewport,
      sceneKey: _baseCharacterSceneKey,
      bone: bone,
      x: axis == 'x' ? value : (current?.x ?? 0.0),
      y: axis == 'y' ? value : (current?.y ?? 0.0),
      z: axis == 'z' ? value : (current?.z ?? 0.0),
    );
  }

  Future<void> _commitFkGesture() async {
    try {
      await _nativeRig.commitGesture();
    } finally {
      _workspace.commitPoseGesture();
    }
  }

  Future<void> _cancelFkGesture() async {
    try {
      await _nativeRig.cancelGesture(
        viewport: _nativeViewport,
        sceneKey: _baseCharacterSceneKey,
      );
    } finally {
      _workspace.cancelPoseGesture();
    }
  }

  Future<void> _undoRig() async {
    if (!_nativeRig.canUndo ||
        !_nativeViewport.hasLoadedScene(_baseCharacterSceneKey)) {
      return;
    }
    await _nativeRig.undo(
      viewport: _nativeViewport,
      sceneKey: _baseCharacterSceneKey,
    );
  }

  Future<void> _redoRig() async {
    if (!_nativeRig.canRedo ||
        !_nativeViewport.hasLoadedScene(_baseCharacterSceneKey)) {
      return;
    }
    await _nativeRig.redo(
      viewport: _nativeViewport,
      sceneKey: _baseCharacterSceneKey,
    );
  }

  @override
  void dispose() {
    _assetCache?.dispose();
    _nativeRig.dispose();
    _nativeViewport.dispose();
    _workspace.dispose();
    super.dispose();
  }

  List<BuilderCloudCategory?> get _cloudNavigationCategories {
    final cloud = _cloudData;
    if (cloud == null) return const <BuilderCloudCategory?>[];

    final categories = <BuilderCloudCategory?>[...cloud.categories];
    final characterMode = cloud.config?.mode == null ||
        cloud.config?.mode == 'character';

    if (characterMode &&
        !cloud.categories.any((category) => category.type == 'pose')) {
      categories.insert(0, null);
    }
    return categories;
  }

  List<(IconData, String)> get _navigationCategories {
    final cloudCategories = _cloudNavigationCategories;
    if (cloudCategories.isEmpty) return fallbackCategories;

    return cloudCategories
        .map(
          (category) => category == null
              ? (Icons.accessibility_new_rounded, 'Pose')
              : (_iconForCategory(category), category.name),
        )
        .toList(growable: false);
  }

  BuilderCloudCategory? get _selectedCloudCategory {
    final categories = _cloudNavigationCategories;
    if (_selectedCategory < 0 || _selectedCategory >= categories.length) {
      return null;
    }
    return categories[_selectedCategory];
  }

  List<BuilderCloudAsset> get _visibleAssets {
    final cloud = _cloudData;
    if (cloud == null) return const <BuilderCloudAsset>[];

    final category = _selectedCloudCategory;
    if (category == null) {
      return cloud.assets
          .where((asset) => asset.type == 'pose')
          .toList(growable: false);
    }

    return cloud.assets
        .where(
          (asset) =>
              asset.categoryId == category.id ||
              asset.categorySlug == category.slug,
        )
        .toList(growable: false);
  }

  void _selectCategory(int index) {
    setState(() {
      _selectedCategory = index;
      _selectedAsset = null;
      _cachedAsset = null;
      _assetError = null;
      _assetLoading = false;
    });
  }

  Future<void> _selectAsset(BuilderAssetChoice choice) async {
    final selectionKey = choice.selectionKey;
    setState(() {
      _selectedAsset = choice;
      _cachedAsset = null;
      _assetError = null;
      _assetLoading = choice.asset.type != 'pose';
    });
    _workspace.setBusy(choice.asset.type != 'pose', status: 'Preparing ${choice.name}');

    if (choice.asset.type == 'pose') {
      return;
    }

    final cache = _assetCache;
    if (cache == null) {
      if (!mounted) return;
      setState(() {
        _assetLoading = false;
        _assetError = 'Cloud asset cache is unavailable.';
      });
      return;
    }

    try {
      final local = await cache.getOrDownload(choice);
      if (!mounted || _selectedAsset?.selectionKey != selectionKey) return;
      setState(() {
        _cachedAsset = local;
        _assetLoading = false;
      });

      _workspace.setBusy(true, status: 'Loading native scene');
      await _nativeViewport.upsertLocalScene(
        sceneKey: _nativeSceneKey(choice),
        path: local.file.path,
        metersPerUnit: _metersPerUnit(choice),
      );

      if (!mounted || _selectedAsset?.selectionKey != selectionKey) return;
      final nativeScene = _nativeViewport.sceneStatus;
      _workspace.setBusy(
        false,
        status: nativeScene?.loadedToGpu == true
            ? 'GPU scene ready'
            : nativeScene?.readiness == 'needs_fbx_decoder'
                ? 'FBX cached · decoder pending'
                : local.cacheHit
                    ? 'Loaded from cache'
                    : 'Asset ready',
      );
    } catch (error) {
      if (!mounted || _selectedAsset?.selectionKey != selectionKey) return;
      setState(() {
        _assetLoading = false;
        _assetError = error.toString();
      });
      _workspace.setBusy(false, status: 'Asset failed');
    }
  }

  String _nativeSceneKey(BuilderAssetChoice choice) {
    final role = choice.asset.role.trim().toLowerCase();
    if (role == 'base_character' || choice.asset.type == 'base_character') {
      return 'role:base_character';
    }
    if (role == 'stand' || role == 'pedestal') {
      return 'role:stand';
    }

    BuilderCloudCategory? category;
    for (final item in _cloudData?.categories ?? const <BuilderCloudCategory>[]) {
      if (item.id == choice.asset.categoryId ||
          item.slug == choice.asset.categorySlug) {
        category = item;
        break;
      }
    }

    final selectionMode = category?.selectionMode.toLowerCase();
    if (selectionMode == 'multiple' ||
        selectionMode == 'multi' ||
        selectionMode == 'many') {
      return 'selection:${choice.selectionKey}';
    }

    final slot = category?.slot?.trim();
    if (slot != null && slot.isNotEmpty) return 'slot:$slot';
    if (choice.asset.categoryId?.isNotEmpty == true) {
      return 'category:${choice.asset.categoryId}';
    }
    if (choice.asset.categorySlug?.isNotEmpty == true) {
      return 'category:${choice.asset.categorySlug}';
    }
    return 'asset:${choice.assetId}';
  }

  double _metersPerUnit(BuilderAssetChoice choice) {
    final metadata = choice.metadata;
    final raw = metadata['metersPerBlenderUnit'] ??
        metadata['meters_per_blender_unit'] ??
        metadata['metersPerUnit'];
    if (raw is num && raw.toDouble().isFinite && raw.toDouble() > 0) {
      return raw.toDouble();
    }

    final sourceUnit = (metadata['sourceUnit'] ?? metadata['unit'])
        ?.toString()
        .trim()
        .toLowerCase();
    return switch (sourceUnit) {
      'mm' || 'millimeter' || 'millimeters' => 0.001,
      'cm' || 'centimeter' || 'centimeters' => 0.01,
      _ => 1.0,
    };
  }

  IconData _iconForCategory(BuilderCloudCategory category) {
    final value = '${category.slug} ${category.type}'.toLowerCase();
    if (value.contains('pose')) return Icons.accessibility_new_rounded;
    if (value.contains('hat') || value.contains('head')) {
      return Icons.checkroom_rounded;
    }
    if (value.contains('base') || value.contains('stand')) {
      return Icons.layers_rounded;
    }
    if (value.contains('hand') || value.contains('sword')) {
      return Icons.sports_martial_arts_rounded;
    }
    if (value.contains('back')) return Icons.shield_outlined;
    if (value.contains('svg')) return Icons.draw_rounded;
    return Icons.category_outlined;
  }

  Future<void> _openProduct(BuilderProductSummary product) async {
    await _nativeRig.reset();
    _workspace.cancelPoseGesture();
    _workspace.setRigVisible(false);
    await _nativeViewport.clearScenes();
    setState(() {
      _selectedProduct = product;
      _cloudLoading = true;
      _cloudError = null;
      _selectedCategory = 0;
      _selectedAsset = null;
      _cachedAsset = null;
      _assetError = null;
      _assetLoading = false;
    });

    try {
      final data = await BuilderCloudRepository().loadBuilderData(product.id);
      if (!mounted || _selectedProduct?.id != product.id) return;
      setState(() {
        _cloudData = data;
        _cloudLoading = false;
      });
      unawaited(_preloadBaseCharacter(data));
    } catch (error) {
      if (!mounted || _selectedProduct?.id != product.id) return;
      setState(() {
        _cloudData = null;
        _cloudLoading = false;
        _cloudError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final desktop = constraints.maxWidth >= 1120;
            return Column(
              children: [
                _TopBar(
                  onToggleTheme: widget.onToggleTheme,
                  cloudReady: widget.cloudReady,
                  selectedProduct: _selectedProduct,
                  onProductSelected: _openProduct,
                  rigController: _nativeRig,
                  onUndo: () => unawaited(_undoRig()),
                  onRedo: () => unawaited(_redoRig()),
                ),
                Expanded(
                  child: compact
                      ? _mobileLayout()
                      : _wideLayout(desktop: desktop),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _wideLayout({required bool desktop}) {
    return Row(
      children: [
        CurrentBuilderCategoryRail(
          selected: _selectedCategory,
          categories: _navigationCategories,
          onSelect: _selectCategory,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Stack(
              children: [
                Positioned.fill(
                  child: NativeViewportSurface(
                    nativeController: _nativeViewport,
                    workspaceController: _workspace,
                    allowDirectOrbit: true,
                    child: BuilderViewport(
                    nativeController: _nativeViewport,
                    rigController: _nativeRig,
                    productName: _selectedProduct?.name,
                    assetCount: _cloudData?.assets.length,
                    cloudLoading: _cloudLoading,
                    cloudError: _cloudError,
                    selectedAssetName: _selectedAsset?.name,
                    localAssetPath: _cachedAsset?.file.path,
                    assetCacheHit: _cachedAsset?.cacheHit,
                    assetLoading: _assetLoading,
                    assetError: _assetError,
                  ),
                  ),
                ),
                Positioned(
                  left: desktop ? 16 : 8,
                  top: desktop ? 54 : 38,
                  child: BuilderToolRail(
                    controller: _workspace,
                    compact: !desktop,
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 8,
                  child: ListenableBuilder(
                    listenable: _workspace,
                    builder: (context, _) => CurrentBuilderViewControls(
                      onView: (preset) {
                        _workspace.setViewPreset(preset.name);
                        unawaited(_nativeViewport.setViewPreset(preset.name));
                      },
                      onOrbit: (dx, dy) {
                        _nativeViewport.orbit(dx, dy);
                        _workspace.markOrbit();
                      },
                      disabled: _workspace.navigationLocked,
                    ),
                  ),
                ),
                if (!desktop)
                  Positioned(
                    right: 10,
                    top: 96,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([_workspace, _nativeRig]),
                      builder: (context, _) => CurrentBuilderRigRail(
                        tablet: true,
                        ikActive: _nativeRig.mode == BridgeRigMode.ik,
                        fkActive: _nativeRig.mode == BridgeRigMode.fk,
                        handOpen: _nativeRig.handOpen,
                        onIk: () => unawaited(
                          _setRigMode(
                            _nativeRig.mode == BridgeRigMode.ik
                                ? BridgeRigMode.none
                                : BridgeRigMode.ik,
                          ),
                        ),
                        onFk: () => unawaited(
                          _setRigMode(
                            _nativeRig.mode == BridgeRigMode.fk
                                ? BridgeRigMode.none
                                : BridgeRigMode.fk,
                          ),
                        ),
                        onOpenHand: () => unawaited(_setHandOpen(true)),
                        onCloseHand: () => unawaited(_setHandOpen(false)),
                      ),
                    ),
                  ),
                Positioned(
                  left: 16,
                  bottom: _cloudData == null ? 14 : 168,
                  child: BuilderViewportStatus(
                    controller: _workspace,
                    nativeController: _nativeViewport,
                    assetName: _selectedAsset?.name,
                    assetLoading: _assetLoading,
                    cacheHit: _cachedAsset?.cacheHit,
                  ),
                ),
                if (_cloudData != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: CloudAssetDock(
                      title: _selectedCloudCategory?.name ?? 'Pose',
                      assets: _visibleAssets,
                      selectedSelectionKey: _selectedAsset?.selectionKey,
                      onSelected: _selectAsset,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (desktop)
          SizedBox(
            width: 332,
            child: _RigPanel(
              rigController: _nativeRig,
              onModeChanged: (mode) => unawaited(_setRigMode(mode)),
              workspace: _workspace,
              jointNames: _nativeViewport.sceneJointNames(_baseCharacterSceneKey),
              onBoneSelected: (bone) => unawaited(_selectFkBone(bone)),
              onFkGestureStart: () => unawaited(_beginFkGesture()),
              onFkAxisChanged: _updateFkAxis,
              onFkGestureEnd: () => unawaited(_commitFkGesture()),
              onFkGestureCancel: () => unawaited(_cancelFkGesture()),
            ),
          ),
      ],
    );
  }

  Widget _mobileLayout() {
    return Stack(
      children: [
        Positioned.fill(
          child: NativeViewportSurface(
            nativeController: _nativeViewport,
            workspaceController: _workspace,
            allowDirectOrbit: false,
            child: BuilderViewport(
            nativeController: _nativeViewport,
            rigController: _nativeRig,
            productName: _selectedProduct?.name,
            assetCount: _cloudData?.assets.length,
            cloudLoading: _cloudLoading,
            cloudError: _cloudError,
            selectedAssetName: _selectedAsset?.name,
            localAssetPath: _cachedAsset?.file.path,
            assetCacheHit: _cachedAsset?.cacheHit,
            assetLoading: _assetLoading,
            assetError: _assetError,
          ),
          ),
        ),
        Positioned(
          left: 0,
          top: 44,
          child: BuilderToolRail(controller: _workspace, compact: true),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: ListenableBuilder(
            listenable: _workspace,
            builder: (context, _) => CurrentBuilderViewControls(
              onView: (preset) {
                _workspace.setViewPreset(preset.name);
                unawaited(_nativeViewport.setViewPreset(preset.name));
              },
              onOrbit: (dx, dy) {
                _nativeViewport.orbit(dx, dy);
                _workspace.markOrbit();
              },
              disabled: _workspace.navigationLocked,
            ),
          ),
        ),
        Positioned(
          right: 8,
          top: 94,
          child: ListenableBuilder(
            listenable: Listenable.merge([_workspace, _nativeRig]),
                      builder: (context, _) => CurrentBuilderRigRail(
              ikActive: _nativeRig.mode == BridgeRigMode.ik,
              fkActive: _nativeRig.mode == BridgeRigMode.fk,
              handOpen: _nativeRig.handOpen,
              onIk: () => unawaited(
                          _setRigMode(
                            _nativeRig.mode == BridgeRigMode.ik
                                ? BridgeRigMode.none
                                : BridgeRigMode.ik,
                          ),
                        ),
              onFk: () => unawaited(
                          _setRigMode(
                            _nativeRig.mode == BridgeRigMode.fk
                                ? BridgeRigMode.none
                                : BridgeRigMode.fk,
                          ),
                        ),
              onOpenHand: () => unawaited(_setHandOpen(true)),
                        onCloseHand: () => unawaited(_setHandOpen(false)),
            ),
          ),
        ),
        Positioned(
          left: 52,
          top: 8,
          right: 92,
          child: BuilderViewportStatus(
            controller: _workspace,
            nativeController: _nativeViewport,
            assetName: _selectedAsset?.name,
            assetLoading: _assetLoading,
            cacheHit: _cachedAsset?.cacheHit,
          ),
        ),
        if (_cloudData != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 72,
            child: CloudAssetDock(
              compact: true,
              title: _selectedCloudCategory?.name ?? 'Pose',
              assets: _visibleAssets,
              selectedSelectionKey: _selectedAsset?.selectionKey,
              onSelected: _selectAsset,
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: CurrentBuilderMobileCategoryNav(
            selected: _selectedCategory,
            categories: _navigationCategories,
            onSelect: _selectCategory,
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onToggleTheme,
    required this.cloudReady,
    required this.selectedProduct,
    required this.onProductSelected,
    required this.rigController,
    required this.onUndo,
    required this.onRedo,
  });

  final VoidCallback onToggleTheme;
  final bool cloudReady;
  final BuilderProductSummary? selectedProduct;
  final ValueChanged<BuilderProductSummary> onProductSelected;
  final NativeRigController rigController;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: rigController,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1120;
        final height = desktop ? 66.0 : 58.0;

        return Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: desktop ? 16 : 10),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.96),
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.055),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: desktop ? 230 : 132,
                child: Row(
                  children: [
                    Container(
                      width: desktop ? 40 : 34,
                      height: desktop ? 40 : 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.primary.withValues(alpha: 0.10),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.46),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.18),
                            blurRadius: 18,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.view_in_ar_rounded,
                        size: desktop ? 22 : 19,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            maxLines: 1,
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: desktop ? 20 : 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                                color: colors.onSurface,
                              ),
                              children: [
                                const TextSpan(text: 'Fresh'),
                                TextSpan(
                                  text: 'STL',
                                  style: TextStyle(color: colors.primary),
                                ),
                              ],
                            ),
                          ),
                          if (desktop)
                            Text(
                              'POSE · CUSTOMIZE · PRINT',
                              style: TextStyle(
                                fontSize: 6.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.1,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (desktop)
                Expanded(
                  child: Center(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _HeaderModeChip(
                            label: 'Builder',
                            icon: Icons.view_in_ar_rounded,
                            active: true,
                          ),
                          const _HeaderModeChip(
                            label: 'Product',
                            icon: Icons.inventory_2_outlined,
                          ),
                          const _HeaderModeChip(
                            label: 'Render',
                            icon: Icons.image_outlined,
                          ),
                          const _HeaderModeChip(
                            label: 'Export',
                            icon: Icons.download_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderIconButton(
                    icon: Icons.undo_rounded,
                    tooltip: 'Undo',
                    onPressed: rigController.canUndo ? onUndo : null,
                  ),
                  _HeaderIconButton(
                    icon: Icons.redo_rounded,
                    tooltip: 'Redo',
                    onPressed: rigController.canRedo ? onRedo : null,
                  ),
                  _HeaderIconButton(
                    icon: Icons.brightness_6_rounded,
                    tooltip: 'Theme',
                    onPressed: onToggleTheme,
                  ),
                  if (desktop || constraints.maxWidth >= 430)
                    CloudProductPickerButton(
                      cloudReady: cloudReady,
                      selectedProduct: selectedProduct,
                      onSelected: onProductSelected,
                    ),
                  CloudAccountButton(cloudReady: cloudReady),
                ],
              ),
            ],
          ),
        );
        },
      ),
    );
  }
}

class _HeaderModeChip extends StatelessWidget {
  const _HeaderModeChip({
    required this.label,
    required this.icon,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      constraints: const BoxConstraints(minWidth: 108),
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 14,
            color: active ? Colors.white : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: active ? Colors.white : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Tooltip(
        message: tooltip,
        child: AnimatedOpacity(
          opacity: onPressed == null ? 0.38 : 1,
          duration: const Duration(milliseconds: 120),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
              child: Icon(icon, size: 17),
            ),
          ),
        ),
      ),
    );
  }
}

class _RigPanel extends StatelessWidget {
  const _RigPanel({
    required this.rigController,
    required this.onModeChanged,
    required this.workspace,
    required this.jointNames,
    required this.onBoneSelected,
    required this.onFkGestureStart,
    required this.onFkAxisChanged,
    required this.onFkGestureEnd,
    required this.onFkGestureCancel,
  });

  final NativeRigController rigController;
  final ValueChanged<BridgeRigMode> onModeChanged;
  final BuilderWorkspaceController workspace;
  final List<String> jointNames;
  final ValueChanged<String?> onBoneSelected;
  final VoidCallback onFkGestureStart;
  final void Function(String axis, double value) onFkAxisChanged;
  final VoidCallback onFkGestureEnd;
  final VoidCallback onFkGestureCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.985),
        border: Border(
          left: BorderSide(color: Theme.of(context).dividerColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 42,
            offset: const Offset(-14, 0),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.07),
                  blurRadius: 22,
                ),
              ],
            ),
            child: ListenableBuilder(
              listenable: Listenable.merge([workspace, rigController]),
              builder: (context, _) {
                final mode = rigController.mode;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Pose & Rig',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      mode == BridgeRigMode.none
                          ? 'Rig controls'
                          : '${mode.name.toUpperCase()} active',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).dividerColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SegmentRigButton(
                              label: 'IK',
                              selected: mode == BridgeRigMode.ik,
                              onTap: () => onModeChanged(
                                mode == BridgeRigMode.ik ? BridgeRigMode.none : BridgeRigMode.ik,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: _SegmentRigButton(
                              label: 'FK',
                              selected: mode == BridgeRigMode.fk,
                              onTap: () => onModeChanged(
                                mode == BridgeRigMode.fk ? BridgeRigMode.none : BridgeRigMode.fk,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {},
                      child: Container(
                        minHeight: 52,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                Icons.auto_awesome_rounded,
                                size: 17,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 9),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'POSE',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Default',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                    if (mode == BridgeRigMode.fk) ...[
                      const SizedBox(height: 14),
                      _FkEditor(
                        jointNames: jointNames,
                        selectedBone: rigController.selectedBone,
                        rotation: rigController.selectedFkRotation,
                        onBoneSelected: onBoneSelected,
                        onGestureStart: onFkGestureStart,
                        onAxisChanged: onFkAxisChanged,
                        onGestureEnd: onFkGestureEnd,
                        onGestureCancel: onFkGestureCancel,
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'Hands',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _HandStateButton(
                            label: 'Open',
                            selected: rigController.handOpen,
                            onTap: () => unawaited(rigController.setHandOpen(true)),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: _HandStateButton(
                            label: 'Close',
                            selected: !rigController.handOpen,
                            onTap: () => unawaited(rigController.setHandOpen(false)),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.face_retouching_natural_rounded, size: 16),
                  label: const Text('Face'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: const Text('Print / Export'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FkEditor extends StatelessWidget {
  const _FkEditor({
    required this.jointNames,
    required this.selectedBone,
    required this.rotation,
    required this.onBoneSelected,
    required this.onGestureStart,
    required this.onAxisChanged,
    required this.onGestureEnd,
    required this.onGestureCancel,
  });

  final List<String> jointNames;
  final String? selectedBone;
  final BridgeEuler? rotation;
  final ValueChanged<String?> onBoneSelected;
  final VoidCallback onGestureStart;
  final void Function(String axis, double value) onAxisChanged;
  final VoidCallback onGestureEnd;
  final VoidCallback onGestureCancel;

  @override
  Widget build(BuildContext context) {
    final selected = jointNames.contains(selectedBone) ? selectedBone : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('FK bone', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          hint: Text(jointNames.isEmpty ? 'Load a skinned character' : 'Select bone'),
          items: jointNames.map((bone) => DropdownMenuItem<String>(
            value: bone,
            child: Text(bone, overflow: TextOverflow.ellipsis),
          )).toList(growable: false),
          onChanged: jointNames.isEmpty ? null : onBoneSelected,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
        ),
        if (selected != null) ...[
          const SizedBox(height: 10),
          _FkAxisSlider(axis: 'X', value: rotation?.x ?? 0, onStart: onGestureStart,
            onChanged: (value) => onAxisChanged('x', value), onEnd: onGestureEnd),
          _FkAxisSlider(axis: 'Y', value: rotation?.y ?? 0, onStart: onGestureStart,
            onChanged: (value) => onAxisChanged('y', value), onEnd: onGestureEnd),
          _FkAxisSlider(axis: 'Z', value: rotation?.z ?? 0, onStart: onGestureStart,
            onChanged: (value) => onAxisChanged('z', value), onEnd: onGestureEnd),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onGestureCancel,
              icon: const Icon(Icons.close_rounded, size: 14),
              label: const Text('Cancel edit'),
            ),
          ),
        ],
      ],
    );
  }
}

class _FkAxisSlider extends StatelessWidget {
  const _FkAxisSlider({
    required this.axis,
    required this.value,
    required this.onStart,
    required this.onChanged,
    required this.onEnd,
  });

  final String axis;
  final double value;
  final VoidCallback onStart;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    const limit = math.pi;
    return Row(
      children: [
        SizedBox(width: 18, child: Text(axis,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900))),
        Expanded(
          child: Slider(
            min: -limit,
            max: limit,
            value: value.clamp(-limit, limit),
            onChangeStart: (_) => onStart(),
            onChanged: onChanged,
            onChangeEnd: (_) => onEnd(),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '${(value * 180 / math.pi).round()}°',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _SegmentRigButton extends StatelessWidget {
  const _SegmentRigButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.24),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: selected ? Colors.white : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _HandStateButton extends StatelessWidget {
  const _HandStateButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        minHeight: 58,
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.16)
              : colors.surfaceContainerHighest.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? colors.primary.withValues(alpha: 0.82)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              label == 'Open'
                  ? Icons.pan_tool_alt_rounded
                  : Icons.back_hand_outlined,
              size: 19,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BuilderViewport extends StatelessWidget {
  const BuilderViewport({
    super.key,
    required this.nativeController,
    required this.rigController,
    this.productName,
    this.assetCount,
    this.cloudLoading = false,
    this.cloudError,
    this.selectedAssetName,
    this.localAssetPath,
    this.assetCacheHit,
    this.assetLoading = false,
    this.assetError,
  });

  final NativeViewportController nativeController;
  final NativeRigController rigController;
  final String? productName;
  final int? assetCount;
  final bool cloudLoading;
  final String? cloudError;
  final String? selectedAssetName;
  final String? localAssetPath;
  final bool? assetCacheHit;
  final bool assetLoading;
  final String? assetError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([nativeController, rigController]),
      builder: (context, _) {
        final textureId = nativeController.textureId;
        final rigMode = rigController.mode;

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF090B19)
                  : const Color(0xFFF7F7FB),
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (textureId != null)
                  FreshBuilderTextureView(textureId: textureId)
                else
                  CustomPaint(
                    painter: _ViewportPainter(
                      grid: Theme.of(context).dividerColor,
                      accent: colors.primary,
                      foreground: colors.onSurface,
                      showRig: rigMode != BridgeRigMode.none,
                      ik: rigMode == BridgeRigMode.ik,
                    ),
                    child: const SizedBox.expand(),
                  ),
                if (nativeController.textureError != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: colors.errorContainer.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Native texture unavailable · using Flutter fallback',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: colors.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ViewportPainter extends CustomPainter {
  const _ViewportPainter({
    required this.grid,
    required this.accent,
    required this.foreground,
    required this.showRig,
    required this.ik,
  });

  final Color grid;
  final Color accent;
  final Color foreground;
  final bool showRig;
  final bool ik;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = grid.withValues(alpha: 0.055),
    );

    final center = Offset(size.width / 2, size.height * 0.55);
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.38)
      ..strokeWidth = 1;

    final horizon = size.height * 0.72;
    for (var i = -8; i <= 8; i++) {
      final x = center.dx + i * math.max(26.0, size.width / 22);
      canvas.drawLine(
        Offset(x, horizon - 85),
        Offset(x, size.height),
        gridPaint,
      );
    }
    for (var i = 0; i < 7; i++) {
      final y = horizon + i * 24;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final bodyPaint = Paint()
      ..color = foreground.withValues(alpha: 0.72)
      ..strokeWidth = math.max(4.0, size.shortestSide * 0.012)
      ..strokeCap = StrokeCap.round;

    final head = center.translate(0, -130);
    final neck = center.translate(0, -92);
    final hips = center.translate(0, 10);
    final leftHand = center.translate(-88, -42);
    final rightHand = center.translate(88, -42);
    final leftFoot = center.translate(-38, 128);
    final rightFoot = center.translate(38, 128);

    canvas.drawCircle(
      head,
      27,
      Paint()..color = foreground.withValues(alpha: 0.7),
    );
    canvas.drawLine(neck, hips, bodyPaint);
    canvas.drawLine(neck, leftHand, bodyPaint);
    canvas.drawLine(neck, rightHand, bodyPaint);
    canvas.drawLine(hips, leftFoot, bodyPaint);
    canvas.drawLine(hips, rightFoot, bodyPaint);

    if (!showRig) return;

    final rigPaint = Paint()
      ..color = accent
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    for (final point in [neck, hips, leftHand, rightHand, leftFoot, rightFoot]) {
      canvas.drawCircle(point, ik ? 7 : 5, rigPaint);
    }
    canvas.drawLine(neck, leftHand, rigPaint);
    canvas.drawLine(neck, rightHand, rigPaint);
    canvas.drawLine(hips, leftFoot, rigPaint);
    canvas.drawLine(hips, rightFoot, rigPaint);
  }

  @override
  bool shouldRepaint(covariant _ViewportPainter oldDelegate) {
    return oldDelegate.showRig != showRig ||
        oldDelegate.ik != ik ||
        oldDelegate.accent != accent ||
        oldDelegate.foreground != foreground ||
        oldDelegate.grid != grid;
  }
}
