import Flutter
import UIKit
import UniformTypeIdentifiers

/// RetroLAN Controller — iOS host.
/// Implements the same MethodChannels as the Android host so the controller works
/// identically on iPhone:
///   - 'retrolan/filepicker': pickFile (UIDocumentPicker) + readChunk (chunked read,
///     so ISO/CD images stream to the TV without loading into phone RAM)
///   - 'retrolan/service': no-op on iOS (no background-kill problem like Android);
///     returning success keeps the Dart side happy.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
    UIDocumentPickerDelegate {

    private var pendingResult: FlutterResult?
    private var pickedURL: URL?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        // Register our host channels through the plugin registry so they get the
        // engine's binary messenger (works across Flutter versions).
        let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RetroLANHost")

        // File picker + chunked reader channel
        let fileChannel = FlutterMethodChannel(
            name: "retrolan/filepicker",
            binaryMessenger: registrar.messenger())
        fileChannel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "pickFile":
                self?.pendingResult = result
                self?.presentPicker()
            case "readChunk":
                guard let args = call.arguments as? [String: Any],
                      let path = args["uri"] as? String,
                      let offset = args["offset"] as? NSNumber,
                      let length = args["length"] as? NSNumber else {
                    result(FlutterError(code: "chunk", message: "bad args", details: nil))
                    return
                }
                self?.readChunk(path: path, offset: offset.int64Value,
                                length: length.intValue, result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // Service channel: no-op on iOS (only Android kills background apps).
        let serviceChannel = FlutterMethodChannel(
            name: "retrolan/service",
            binaryMessenger: registrar.messenger())
        serviceChannel.setMethodCallHandler { _, result in
            result(true)
        }
    }

    // MARK: - File picker

    private func presentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        DispatchQueue.main.async {
            self.window?.rootViewController?.present(picker, animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            pendingResult?(nil)
            pendingResult = nil
            return
        }
        // Security-scoped: must start accessing to read outside the sandbox.
        let ok = url.startAccessingSecurityScopedResource()
        pickedURL = url
        var size: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let s = attrs[.size] as? NSNumber {
            size = s.int64Value
        }
        pendingResult?([
            "name": url.lastPathComponent,
            "size": size,
            "uri": ok ? url.path : url.absoluteString,
        ])
        pendingResult = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingResult?(nil)
        pendingResult = nil
    }

    // MARK: - Chunked read (streams big files without loading them into RAM)

    private func readChunk(path: String, offset: Int64, length: Int, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url: URL
                if path.hasPrefix("file://") {
                    url = URL(string: path)!
                } else {
                    url = URL(fileURLWithPath: path)
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(offset))
                let data = try handle.read(upToCount: length) ?? Data()
                result(FlutterStandardTypedData(bytes: data)) // Uint8List to Dart
            } catch {
                result(FlutterError(code: "chunk", message: error.localizedDescription, details: nil))
            }
        }
    }
}
