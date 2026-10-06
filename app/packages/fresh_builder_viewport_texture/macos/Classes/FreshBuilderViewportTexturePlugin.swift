import Cocoa
import CoreVideo
import Darwin
import FlutterMacOS

private typealias CaptureEnabledFn = @convention(c) (UInt8) -> Void
private typealias CopyLatestFrameFn = @convention(c) (
    UnsafeMutablePointer<UInt8>?,
    Int,
    UnsafeMutablePointer<UInt32>?,
    UnsafeMutablePointer<UInt32>?,
    UnsafeMutablePointer<UInt64>?
) -> Int

private final class FreshBuilderPixelTexture: NSObject, FlutterTexture {
    private let copyLatestFrame: CopyLatestFrameFn
    private let lock = NSLock()
    private var rgba = [UInt8]()
    private var pixelBuffer: CVPixelBuffer?
    private var width = 0
    private var height = 0
    private var generation: UInt64 = 0

    init(copyLatestFrame: @escaping CopyLatestFrameFn) {
        self.copyLatestFrame = copyLatestFrame
        super.init()
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        defer { lock.unlock() }

        var frameWidth: UInt32 = 0
        var frameHeight: UInt32 = 0
        var frameGeneration = generation

        let required = copyLatestFrame(
            nil,
            0,
            &frameWidth,
            &frameHeight,
            &frameGeneration
        )

        guard required > 0, frameWidth > 0, frameHeight > 0 else {
            return nil
        }

        rgba = Array(repeating: 0, count: required)
        let copied = rgba.withUnsafeMutableBufferPointer { buffer in
            copyLatestFrame(
                buffer.baseAddress,
                buffer.count,
                &frameWidth,
                &frameHeight,
                &frameGeneration
            )
        }

        guard copied == required else {
            return nil
        }

        let nextWidth = Int(frameWidth)
        let nextHeight = Int(frameHeight)
        if pixelBuffer == nil || width != nextWidth || height != nextHeight {
            pixelBuffer = createPixelBuffer(width: nextWidth, height: nextHeight)
            width = nextWidth
            height = nextHeight
        }

        guard let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let destination = base.assumingMemoryBound(to: UInt8.self)
        let sourceRowBytes = nextWidth * 4

        rgba.withUnsafeBytes { sourceBytes in
            guard let source = sourceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            for y in 0..<nextHeight {
                let srcRow = source.advanced(by: y * sourceRowBytes)
                let dstRow = destination.advanced(by: y * bytesPerRow)

                for x in 0..<nextWidth {
                    let src = srcRow.advanced(by: x * 4)
                    let dst = dstRow.advanced(by: x * 4)
                    dst[0] = src[2]
                    dst[1] = src[1]
                    dst[2] = src[0]
                    dst[3] = src[3]
                }
            }
        }

        generation = frameGeneration
        return Unmanaged.passRetained(pixelBuffer)
    }

    private func createPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer
        )

        return status == kCVReturnSuccess ? buffer : nil
    }
}

public final class FreshBuilderViewportTexturePlugin: NSObject, FlutterPlugin {
    private static let channelName = "fresh_builder/viewport_texture"
    private static let libraryName = "libfresh_builder_rust.dylib"

    private let registrar: FlutterPluginRegistrar
    private var texture: FreshBuilderPixelTexture?
    private var textureId: Int64 = -1

    private var rustModule: UnsafeMutableRawPointer?
    private var captureEnabled: CaptureEnabledFn?
    private var copyLatestFrame: CopyLatestFrameFn?

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let instance = FreshBuilderViewportTexturePlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "create":
            guard createTexture() else {
                result(FlutterError(
                    code: "native_texture_unavailable",
                    message: "Could not resolve the Fresh Builder Rust frame bridge.",
                    details: nil
                ))
                return
            }
            result(textureId)

        case "markFrame":
            if textureId >= 0 {
                registrar.textures.textureFrameAvailable(textureId)
            }
            result(nil)

        case "dispose":
            disposeTexture()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    deinit {
        disposeTexture()
        if let rustModule {
            dlclose(rustModule)
        }
    }

    private func resolveRustBridge() -> Bool {
        if captureEnabled != nil && copyLatestFrame != nil {
            return true
        }

        let candidates: [String?] = [
            nil,
            Bundle.main.privateFrameworksPath.map {
                ($0 as NSString).appendingPathComponent(Self.libraryName)
            },
            (Bundle.main.bundlePath as NSString)
                .appendingPathComponent("Contents/Frameworks/\(Self.libraryName)"),
            Self.libraryName,
        ]

        for candidate in candidates {
            guard let handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) else {
                continue
            }

            guard
                let captureSymbol = dlsym(
                    handle,
                    "fresh_builder_frame_capture_enabled"
                ),
                let copySymbol = dlsym(
                    handle,
                    "fresh_builder_copy_latest_frame"
                )
            else {
                dlclose(handle)
                continue
            }

            rustModule = handle
            captureEnabled = unsafeBitCast(
                captureSymbol,
                to: CaptureEnabledFn.self
            )
            copyLatestFrame = unsafeBitCast(
                copySymbol,
                to: CopyLatestFrameFn.self
            )
            return true
        }

        return false
    }

    private func createTexture() -> Bool {
        if textureId >= 0 {
            return true
        }

        guard resolveRustBridge(),
              let copyLatestFrame,
              let captureEnabled
        else {
            return false
        }

        let texture = FreshBuilderPixelTexture(
            copyLatestFrame: copyLatestFrame
        )
        let id = registrar.textures.register(texture)
        guard id >= 0 else {
            return false
        }

        self.texture = texture
        textureId = id
        captureEnabled(1)
        return true
    }

    private func disposeTexture() {
        captureEnabled?(0)

        if textureId >= 0 {
            registrar.textures.unregisterTexture(textureId)
        }

        textureId = -1
        texture = nil
    }
}
