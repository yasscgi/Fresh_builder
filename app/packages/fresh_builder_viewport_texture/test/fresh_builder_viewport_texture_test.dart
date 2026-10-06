import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_builder_viewport_texture/fresh_builder_viewport_texture.dart';

void main() {
  test('texture bridge reports Windows-only support in first desktop stage', () {
    final bridge = FreshBuilderViewportTexture();
    final expected =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    expect(bridge.supported, expected);
    expect(bridge.textureId, isNull);
  });
}
