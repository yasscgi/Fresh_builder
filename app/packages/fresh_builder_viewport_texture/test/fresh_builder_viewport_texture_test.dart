import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_builder_viewport_texture/fresh_builder_viewport_texture.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('texture bridge reports Android support', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(FreshBuilderViewportTexture().supported, isTrue);
  });

  test('texture bridge reports iOS support', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(FreshBuilderViewportTexture().supported, isTrue);
  });

  test('texture bridge reports desktop support', () {
    for (final platform in const [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(FreshBuilderViewportTexture().supported, isTrue);
    }
  });
}
