import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_builder_viewport_texture/fresh_builder_viewport_texture.dart';

void main() {
  test('texture bridge reports support on native desktop platforms', () {
    final bridge = FreshBuilderViewportTexture();
    final expected = !kIsWeb &&
        {
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform);
    expect(bridge.supported, expected);
    expect(bridge.textureId, isNull);
  });
}
