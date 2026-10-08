package com.freshstl.fresh_builder_viewport_texture;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.SurfaceTexture;
import android.view.Surface;

import androidx.annotation.NonNull;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;

public final class FreshBuilderViewportTexturePlugin
    implements FlutterPlugin, MethodChannel.MethodCallHandler {

  private static final String CHANNEL = "fresh_builder/viewport_texture";

  static {
    System.loadLibrary("fresh_builder_viewport_texture");
  }

  private MethodChannel channel;
  private TextureRegistry textureRegistry;
  private TextureRegistry.SurfaceTextureEntry textureEntry;
  private Surface surface;
  private Bitmap bitmap;

  private static native boolean nativeSetCapture(boolean enabled);
  private static native byte[] nativeReadFrame();

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    textureRegistry = binding.getTextureRegistry();
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    disposeTexture();
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    textureRegistry = null;
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    switch (call.method) {
      case "create":
        if (!createTexture()) {
          result.error(
              "native_texture_unavailable",
              "Could not resolve the Fresh Builder Rust frame bridge.",
              null);
          return;
        }
        result.success(textureEntry.id());
        return;

      case "markFrame":
        if (textureEntry != null) {
          drawLatestFrame();
        }
        result.success(null);
        return;

      case "dispose":
        disposeTexture();
        result.success(null);
        return;

      default:
        result.notImplemented();
    }
  }

  private boolean createTexture() {
    if (textureEntry != null) {
      return true;
    }
    if (textureRegistry == null || !nativeSetCapture(true)) {
      return false;
    }

    textureEntry = textureRegistry.createSurfaceTexture();
    SurfaceTexture surfaceTexture = textureEntry.surfaceTexture();
    surface = new Surface(surfaceTexture);
    return true;
  }

  private void disposeTexture() {
    nativeSetCapture(false);

    if (surface != null) {
      surface.release();
      surface = null;
    }
    if (textureEntry != null) {
      textureEntry.release();
      textureEntry = null;
    }
    if (bitmap != null) {
      bitmap.recycle();
      bitmap = null;
    }
  }

  private void drawLatestFrame() {
    if (textureEntry == null || surface == null) {
      return;
    }

    byte[] packed = nativeReadFrame();
    if (packed == null || packed.length < 8) {
      return;
    }

    ByteBuffer header = ByteBuffer.wrap(packed, 0, 8).order(ByteOrder.LITTLE_ENDIAN);
    int width = header.getInt();
    int height = header.getInt();
    if (width <= 0 || height <= 0 || packed.length != 8 + width * height * 4) {
      return;
    }

    SurfaceTexture surfaceTexture = textureEntry.surfaceTexture();
    surfaceTexture.setDefaultBufferSize(width, height);

    if (bitmap == null || bitmap.getWidth() != width || bitmap.getHeight() != height) {
      if (bitmap != null) {
        bitmap.recycle();
      }
      bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
    }

    int[] pixels = new int[width * height];
    int src = 8;
    for (int i = 0; i < pixels.length; i++) {
      int r = packed[src] & 0xff;
      int g = packed[src + 1] & 0xff;
      int b = packed[src + 2] & 0xff;
      int a = packed[src + 3] & 0xff;
      pixels[i] = Color.argb(a, r, g, b);
      src += 4;
    }
    bitmap.setPixels(pixels, 0, width, 0, 0, width, height);

    Canvas canvas = null;
    try {
      canvas = surface.lockCanvas(null);
      canvas.drawBitmap(bitmap, 0.0f, 0.0f, null);
    } finally {
      if (canvas != null) {
        surface.unlockCanvasAndPost(canvas);
      }
    }
  }
}
