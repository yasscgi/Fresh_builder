import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'src/cloud/builder_cloud_models.dart';
import 'src/cloud/builder_cloud_repository.dart';
import 'src/cloud/builder_product_repository.dart';
import 'src/cloud/cloud_account_button.dart';
import 'src/cloud/cloud_asset_dock.dart';
import 'src/cloud/cloud_product_picker_button.dart';
import 'src/cloud/supabase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cloudReady = await FreshSupabaseBootstrap.initialize();
  runApp(FreshBuilderApp(cloudReady: cloudReady));
}

enum RigMode { none, ik, fk }

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
      surface: dark ? const Color(0xFF121019) : const Color(0xFFF8F7FB),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF0B0910) : const Color(0xFFF3F1F7),
      dividerColor:
          (dark ? Colors.white : Colors.black).withValues(alpha: 0.08),
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
  RigMode _rigMode = RigMode.none;
  int _selectedCategory = 0;
  BuilderProductSummary? _selectedProduct;
  BuilderCloudData? _cloudData;
  String? _selectedAssetId;
  bool _cloudLoading = false;
  String? _cloudError;

  static const fallbackCategories = <(IconData, String)>[
    (Icons.accessibility_new_rounded, 'Pose'),
    (Icons.checkroom_rounded, 'Hat'),
    (Icons.shield_outlined, 'Back'),
    (Icons.sports_martial_arts_rounded, 'Hand'),
    (Icons.layers_rounded, 'Base'),
  ];

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
      _selectedAssetId = null;
    });
  }

  void _selectAsset(BuilderCloudAsset asset) {
    setState(() => _selectedAssetId = asset.id);
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
    setState(() {
      _selectedProduct = product;
      _cloudLoading = true;
      _cloudError = null;
      _selectedCategory = 0;
      _selectedAssetId = null;
    });

    try {
      final data = await BuilderCloudRepository().loadBuilderData(product.id);
      if (!mounted || _selectedProduct?.id != product.id) return;
      setState(() {
        _cloudData = data;
        _cloudLoading = false;
      });
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
        _CategoryRail(
          selected: _selectedCategory,
          categories: _navigationCategories,
          onSelect: _selectCategory,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Expanded(
                  child: BuilderViewport(
                    rigMode: _rigMode,
                    productName: _selectedProduct?.name,
                    assetCount: _cloudData?.assets.length,
                    cloudLoading: _cloudLoading,
                    cloudError: _cloudError,
                  ),
                ),
                if (_cloudData != null) ...[
                  const SizedBox(height: 8),
                  CloudAssetDock(
                    assets: _visibleAssets,
                    selectedAssetId: _selectedAssetId,
                    onSelected: _selectAsset,
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(
          width: desktop ? 220 : 176,
          child: _RigPanel(
            mode: _rigMode,
            onModeChanged: (mode) => setState(() => _rigMode = mode),
          ),
        ),
      ],
    );
  }

  Widget _mobileLayout() {
    return Stack(
      children: [
        Positioned.fill(
          child: BuilderViewport(
            rigMode: _rigMode,
            productName: _selectedProduct?.name,
            assetCount: _cloudData?.assets.length,
            cloudLoading: _cloudLoading,
            cloudError: _cloudError,
          ),
        ),
        Positioned(
          left: 8,
          top: 16,
          bottom: 88,
          child: _CategoryRail(
            compact: true,
            selected: _selectedCategory,
            categories: _navigationCategories,
            onSelect: _selectCategory,
          ),
        ),
        if (_cloudData != null)
          Positioned(
            left: 72,
            right: 8,
            bottom: 82,
            child: CloudAssetDock(
              assets: _visibleAssets,
              selectedAssetId: _selectedAssetId,
              onSelected: _selectAsset,
            ),
          ),
        Positioned(
          left: 72,
          right: 8,
          bottom: 10,
          child: _MobileRigBar(
            mode: _rigMode,
            onModeChanged: (mode) => setState(() => _rigMode = mode),
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
  });

  final VoidCallback onToggleTheme;
  final bool cloudReady;
  final BuilderProductSummary? selectedProduct;
  final ValueChanged<BuilderProductSummary> onProductSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 18),
          ),
          const SizedBox(width: 10),
          const Text(
            'Fresh Builder',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.undo_rounded, size: 19),
            tooltip: 'Undo',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.redo_rounded, size: 19),
            tooltip: 'Redo',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6_rounded, size: 19),
            tooltip: 'Theme',
            onPressed: onToggleTheme,
          ),
          CloudProductPickerButton(
            cloudReady: cloudReady,
            selectedProduct: selectedProduct,
            onSelected: onProductSelected,
          ),
          CloudAccountButton(cloudReady: cloudReady),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Text(
              'CORE BOOTSTRAP',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.greenAccent,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: (cloudReady ? Colors.cyan : Colors.orange)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              cloudReady ? 'CLOUD READY' : 'LOCAL MODE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: cloudReady
                    ? Colors.cyanAccent
                    : Colors.orangeAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.selected,
    required this.categories,
    required this.onSelect,
    this.compact = false,
  });

  final int selected;
  final List<(IconData, String)> categories;
  final ValueChanged<int> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: compact ? 56 : 74,
      margin: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: compact ? 0.92 : 1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final item = categories[index];
          final active = index == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Tooltip(
              message: item.$2,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: compact ? 44 : 54,
                  decoration: BoxDecoration(
                    color: active
                        ? colors.primary.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? colors.primary.withValues(alpha: 0.55)
                          : Colors.transparent,
                    ),
                  ),
                  child: Icon(
                    item.$1,
                    size: 21,
                    color: active ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RigPanel extends StatelessWidget {
  const _RigPanel({required this.mode, required this.onModeChanged});

  final RigMode mode;
  final ValueChanged<RigMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'POSE RIG',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _RigButton(
            label: 'IK',
            icon: Icons.open_with_rounded,
            selected: mode == RigMode.ik,
            onTap: () =>
                onModeChanged(mode == RigMode.ik ? RigMode.none : RigMode.ik),
          ),
          const SizedBox(height: 7),
          _RigButton(
            label: 'FK',
            icon: Icons.rotate_right_rounded,
            selected: mode == RigMode.fk,
            onTap: () =>
                onModeChanged(mode == RigMode.fk ? RigMode.none : RigMode.fk),
          ),
          const SizedBox(height: 7),
          const _RigButton(
            label: 'Hands',
            icon: Icons.pan_tool_alt_rounded,
          ),
          const Spacer(),
          Text(
            'Flutter owns UI. Live rig state and final pose commits belong to Rust.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _MobileRigBar extends StatelessWidget {
  const _MobileRigBar({required this.mode, required this.onModeChanged});

  final RigMode mode;
  final ValueChanged<RigMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RigButton(
              label: 'IK',
              icon: Icons.open_with_rounded,
              selected: mode == RigMode.ik,
              onTap: () =>
                  onModeChanged(mode == RigMode.ik ? RigMode.none : RigMode.ik),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _RigButton(
              label: 'FK',
              icon: Icons.rotate_right_rounded,
              selected: mode == RigMode.fk,
              onTap: () =>
                  onModeChanged(mode == RigMode.fk ? RigMode.none : RigMode.fk),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: _RigButton(
              label: 'Hand',
              icon: Icons.pan_tool_alt_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _RigButton extends StatelessWidget {
  const _RigButton({
    required this.label,
    required this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.18)
          : colors.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? colors.primary.withValues(alpha: 0.62)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: selected ? colors.primary : null),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? colors.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BuilderViewport extends StatelessWidget {
  const BuilderViewport({
    super.key,
    required this.rigMode,
    this.productName,
    this.assetCount,
    this.cloudLoading = false,
    this.cloudError,
  });

  final RigMode rigMode;
  final String? productName;
  final int? assetCount;
  final bool cloudLoading;
  final String? cloudError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ViewportPainter(
                grid: Theme.of(context).dividerColor,
                accent: colors.primary,
                foreground: colors.onSurface,
                showRig: rigMode != RigMode.none,
                ik: rigMode == RigMode.ik,
              ),
            ),
          ),
          const Positioned(
            top: 12,
            right: 12,
            child: _ViewCube(),
          ),
          if (productName != null)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cloudLoading)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        cloudError == null
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_off_rounded,
                        size: 15,
                        color: cloudError == null
                            ? Colors.cyanAccent
                            : colors.error,
                      ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        cloudError != null
                            ? 'Cloud load failed'
                            : '$productName · ${assetCount ?? 0} assets',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            bottom: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Text(
                rigMode == RigMode.none
                    ? 'NAVIGATE'
                    : rigMode.name.toUpperCase(),
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewCube extends StatelessWidget {
  const _ViewCube();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: const Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.view_in_ar_rounded, size: 29),
          Positioned(top: 4, child: Text('TOP', style: TextStyle(fontSize: 8))),
          Positioned(
            bottom: 4,
            child: Text('FRONT', style: TextStyle(fontSize: 8)),
          ),
        ],
      ),
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
