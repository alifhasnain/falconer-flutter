import Flutter
import Foundation

/// FalconerPlugin — the thin iOS plugin.
///
/// It owns only the channel wiring; all real work is delegated to a
/// `FalconerEngine` chosen at **compile time**:
///
///     #if DEBUG   -> RealFalconerEngine (SwiftUI UI, SQLite, capture)
///     #else       -> NoOpFalconerEngine (inert)
///
/// Because this class references a concrete engine only inside `#if DEBUG`, a
/// release build has no compile edge to the inspector, so the real engine and
/// everything it pulls in are absent from the release binary (Method A, the iOS
/// mirror of Android's ServiceLoader + variant-scoped deps). Log calls are
/// fire-and-forget — each replies immediately.
public class FalconerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private let engine: FalconerEngine
    private var countTask: Task<Void, Never>?

    override init() {
        #if DEBUG
        engine = RealFalconerEngine()
        #else
        engine = NoOpFalconerEngine()
        #endif
        super.init()
        engine.attach()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FalconerPlugin()

        let methodChannel = FlutterMethodChannel(
            name: FalconerChannels.method,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: FalconerChannels.transactionCountEvent,
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        countTask?.cancel()
        countTask = nil
        engine.detach()
    }

    // MARK: - MethodCallHandler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case FalconerMethods.ping:
            result("pong")
        case FalconerMethods.configure:
            if let args = call.arguments as? [String: Any] { engine.configure(args) }
            result(nil)
        case FalconerMethods.logRequest:
            if let args = call.arguments as? [String: Any] { engine.logRequest(args) }
            result(nil)
        case FalconerMethods.logResponse:
            if let args = call.arguments as? [String: Any] { engine.logResponse(args) }
            result(nil)
        case FalconerMethods.logError:
            if let args = call.arguments as? [String: Any] { engine.logError(args) }
            result(nil)
        case FalconerMethods.clearTransactions:
            engine.clear()
            result(nil)
        case FalconerMethods.launchUi:
            engine.launchUi()
            result(nil)
        case FalconerMethods.requestNotificationPermission:
            // iOS entry point is shake-to-open + programmatic launchUi (there is
            // no notification-to-task model). Nothing to grant; resolve true so
            // the shared Dart API stays consistent. See DOCUMENTATION.md §iOS.
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler (live transaction count)

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        countTask?.cancel()
        let stream = engine.observeCount()
        countTask = Task {
            for await count in stream {
                if Task.isCancelled { break }
                await MainActor.run { events(count) }
            }
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        countTask?.cancel()
        countTask = nil
        return nil
    }
}
