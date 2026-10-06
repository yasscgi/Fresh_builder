import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'builder_repository.dart';

class LocalBuilderAsset {
  const LocalBuilderAsset({
    required this.asset,
    required this.file,
    required this.cacheHit,
  });

  final ResolvedBuilderAsset asset;
  final File file;
  final bool cacheHit;
}

class BuilderAssetCache {
  BuilderAssetCache({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  Directory? _cacheDirectory;
  final Map<String, Future<LocalBuilderAsset>> _inFlight = {};

  Future<LocalBuilderAsset> getOrDownload(
    ResolvedBuilderAsset asset,
  ) {
    return _inFlight.putIfAbsent(
      asset.cacheKey,
      () => _getOrDownload(asset).whenComplete(
        () => _inFlight.remove(asset.cacheKey),
      ),
    );
  }

  Future<LocalBuilderAsset> _getOrDownload(
    ResolvedBuilderAsset asset,
  ) async {
    final directory = await _directory();
    final extension = _safeExtension(asset.sourceFormat);
    final digest = sha256.convert(asset.cacheKey.codeUnits).toString();
    final file = File('${directory.path}/$digest.$extension');

    if (await file.exists() && await file.length() > 0) {
      return LocalBuilderAsset(
        asset: asset,
        file: file,
        cacheHit: true,
      );
    }

    final response = await _httpClient.get(Uri.parse(asset.modelUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Builder asset download failed with HTTP ${response.statusCode}.',
        uri: Uri.parse(asset.modelUrl),
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

    return LocalBuilderAsset(
      asset: asset,
      file: file,
      cacheHit: false,
    );
  }

  Future<void> remove(ResolvedBuilderAsset asset) async {
    final directory = await _directory();
    final extension = _safeExtension(asset.sourceFormat);
    final digest = sha256.convert(asset.cacheKey.codeUnits).toString();
    final file = File('${directory.path}/$digest.$extension');
    if (await file.exists()) await file.delete();
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

  void dispose() {
    _httpClient.close();
  }
}
