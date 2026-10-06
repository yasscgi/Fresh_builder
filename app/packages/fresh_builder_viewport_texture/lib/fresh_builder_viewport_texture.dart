import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class FreshBuilderViewportTexture {
  FreshBuilderViewportTexture();

  static const MethodChannel _channel =
      MethodChannel('fresh_builder/viewport_texture');

  int? _textureId;

  bool get supported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  int? get textureId => _textureId;

  Future<int?> create() async {
    if (!supported) return null;
    if (_textureId != null) return _textureId;

    final id = await _channel.invokeMethod<int>('create');
    _textureId = id;
    return id;
  }

  Future<void> markFrame() async {
    if (!supported || _textureId == null) return;
    await _channel.invokeMethod<void>('markFrame');
  }

  Future<void> dispose() async {
    if (!supported || _textureId == null) return;
    try {
      await _channel.invokeMethod<void>('dispose');
    } finally {
      _textureId = null;
    }
  }
}

class FreshBuilderTextureView extends StatelessWidget {
  const FreshBuilderTextureView({
    super.key,
    required this.textureId,
  });

  final int textureId;

  @override
  Widget build(BuildContext context) {
    return Texture(
      textureId: textureId,
      filterQuality: FilterQuality.medium,
    );
  }
}
