import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'builder_asset_url_resolver.dart';
import 'builder_cloud_models.dart';

final class CachedBuilderAsset {
  const CachedBuilderAsset({
    required this.choice,
    required this.file,
    required this.sourceFormat,
    required this.metersPerUnit,
    required this.cacheHit,
    required this.version,
  });

  final BuilderAssetChoice choice;
  final File file;
  final String sourceFormat;
  final double metersPerUnit;
  final bool cacheHit;
  final String? version;
}

final class BuilderAssetDiskCache {
  BuilderAssetDiskCache({
    BuilderAssetUrlResolver? resolver,
    http.Client? httpClient,
  })  : _resolver = resolver ?? BuilderAssetUrlResolver(),
        _httpClient = httpClient ?? http.Client();

  final BuilderAssetUrlResolver _resolver;
  final http.Client _httpClient;
  Directory? _cacheDirectory;
  final Map<String, Future<CachedBuilderAsset>> _inFlight = {};
  final Map<String, Set<String>> _knownFiles = {};

  Future<CachedBuilderAsset> getOrDownload(BuilderAssetChoice choice) {
    final key = choice.selectionKey;
    return _inFlight.putIfAbsent(
      key,
      () => _getOrDownload(choice).whenComplete(
        () => _inFlight.remove(key),
      ),
    );
  }

  Future<CachedBuilderAsset> _getOrDownload(
    BuilderAssetChoice choice,
  ) async {
    final resolved = await _resolver.resolve(
      assetId: choice.assetId,
      kind: 'model',
      variationId: choice.variationId,
    );

    final sourceFormat = _sourceFormat(choice);
    final extension = _safeExtension(sourceFormat);
    final metersPerUnit = _metersPerUnit(choice);
    final version = resolved.version ?? choice.asset.updatedAt ?? 'unversioned';
    final cacheKey = '${choice.selectionKey}|$version|$extension';
    final digest = sha256.convert(cacheKey.codeUnits).toString();

    final directory = await _directory();
    final file = File('${directory.path}/$digest.$extension');

    if (await file.exists() && await file.length() > 0) {
      _remember(choice.selectionKey, file);
      return CachedBuilderAsset(
        choice: choice,
        file: file,
        sourceFormat: sourceFormat,
        metersPerUnit: metersPerUnit,
        cacheHit: true,
        version: resolved.version,
      );
    }

    final response = await _httpClient.get(resolved.uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Builder asset download failed with HTTP ${response.statusCode}.',
        uri: resolved.uri,
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw const FileSystemException(
        'Builder asset download returned an empty file.',
      );
    }

    final temp = File('${file.path}.part');
    await temp.writeAsBytes(response.bodyBytes, flush: true);

    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
    _remember(choice.selectionKey, file);

    return CachedBuilderAsset(
      choice: choice,
      file: file,
      sourceFormat: sourceFormat,
      metersPerUnit: metersPerUnit,
      cacheHit: false,
      version: resolved.version,
    );
  }

  Future<void> invalidate(BuilderAssetChoice choice) async {
    _resolver.invalidateAsset(choice.assetId);
    final paths = _knownFiles.remove(choice.selectionKey);
    if (paths == null) return;

    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void _remember(String selectionKey, File file) {
    _knownFiles.putIfAbsent(selectionKey, () => <String>{}).add(file.path);
  }

  String _sourceFormat(BuilderAssetChoice choice) {
    final metadata = choice.metadata;
    final declared = metadata['sourceFormat']?.toString().trim().toLowerCase();
    if (declared != null && declared.isNotEmpty) {
      return declared.replaceFirst('.', '');
    }

    final source = choice.variation?.modelRef ?? choice.asset.modelRef ?? '';
    final clean = source.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot >= 0 && dot < clean.length - 1) {
      return clean.substring(dot + 1).toLowerCase();
    }

    return 'bin';
  }

  double _metersPerUnit(BuilderAssetChoice choice) {
    final raw = choice.metadata['metersPerBlenderUnit'];
    return raw is num ? raw.toDouble() : 1.0;
  }

  String _safeExtension(String format) {
    final normalized = format.trim().toLowerCase().replaceAll('.', '');
    switch (normalized) {
      case 'fbx':
      case 'glb':
      case 'gltf':
      case 'stl':
      case '3mf':
        return normalized;
      default:
        return 'bin';
    }
  }

  Future<Directory> _directory() async {
    final existing = _cacheDirectory;
    if (existing != null) return existing;

    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/fresh_builder/assets');
    await directory.create(recursive: true);
    _cacheDirectory = directory;
    return directory;
  }

  void dispose() {
    _httpClient.close();
  }
}
