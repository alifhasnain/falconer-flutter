package dev.alifhasnain.falconer

import android.content.Context
import dev.alifhasnain.falconer.channel.MethodNames
import dev.alifhasnain.falconer.engine.FalconerEngine
import dev.alifhasnain.falconer.notification.NotificationPermission
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import java.util.ServiceLoader

/**
 * FalconerPlugin — the thin plugin. It owns only the channel wiring and the
 * (light) notification-permission flow; all real work is delegated to a
 * [FalconerEngine] discovered at runtime via [ServiceLoader].
 *
 * The engine is whichever implementation is linked for the current build
 * variant (see `android/build.gradle`):
 *   debug   -> falconer-impl -> RealFalconerEngine (Compose UI, SQLDelight, …)
 *   release -> falconer-noop -> NoOpFalconerEngine (inert)
 *
 * Because this class references ONLY the interface, a release build linking the
 * no-op has no compile edge to the inspector, so R8 strips Compose / SQLDelight /
 * the UI and the no-op AAR contributes no manifest components — the inspector is
 * physically absent (RELEASE_STRIPPING.md, Method A). Log calls stay
 * fire-and-forget; each replies `success(null)` immediately.
 */
class FalconerPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    // Only for collecting the count Flow onto the platform thread; the engine
    // owns its own work scope. Main so the EventSink is touched on the UI thread.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var countJob: Job? = null

    private var appContext: Context? = null
    private val notificationPermission = NotificationPermission()
    private var activityBinding: ActivityPluginBinding? = null

    private val engine: FalconerEngine =
        ServiceLoader.load(FalconerEngine::class.java, FalconerEngine::class.java.classLoader)
            .firstOrNull() ?: NoEngine

    // FlutterPlugin -----------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        engine.attach(binding.applicationContext)

        methodChannel = MethodChannel(binding.binaryMessenger, MethodNames.CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, MethodNames.TRANSACTION_COUNT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        countJob?.cancel()
        engine.detach()
        scope.cancel()
    }

    // MethodCallHandler -------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            MethodNames.PING -> result.success("pong")
            MethodNames.CONFIGURE -> {
                (call.arguments as? Map<*, *>)?.let(engine::configure); result.success(null)
            }
            MethodNames.LOG_REQUEST -> {
                (call.arguments as? Map<*, *>)?.let(engine::logRequest); result.success(null)
            }
            MethodNames.LOG_RESPONSE -> {
                (call.arguments as? Map<*, *>)?.let(engine::logResponse); result.success(null)
            }
            MethodNames.LOG_ERROR -> {
                (call.arguments as? Map<*, *>)?.let(engine::logError); result.success(null)
            }
            MethodNames.CLEAR_TRANSACTIONS -> {
                engine.clear(); result.success(null)
            }
            MethodNames.LAUNCH_UI -> {
                appContext?.let(engine::launchUi); result.success(null)
            }
            MethodNames.REQUEST_NOTIFICATION_PERMISSION ->
                notificationPermission.request(activityBinding) { granted -> result.success(granted) }
            else -> result.notImplemented()
        }
    }

    // EventChannel.StreamHandler ---------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        countJob?.cancel()
        countJob = scope.launch {
            engine.observeCount().collectLatest { count -> events?.success(count) }
        }
    }

    override fun onCancel(arguments: Any?) {
        countJob?.cancel()
        countJob = null
    }

    // ActivityAware (binding captured for the notification-permission flow) ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(notificationPermission)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(notificationPermission)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(notificationPermission)
        activityBinding = null
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(notificationPermission)
        activityBinding = null
    }

    /**
     * Defensive fallback if no engine is on the classpath. In practice one of
     * falconer-impl / falconer-noop is always linked, so this is never used.
     */
    private object NoEngine : FalconerEngine {
        override fun attach(context: Context) = Unit
        override fun detach() = Unit
        override fun configure(args: Map<*, *>) = Unit
        override fun logRequest(args: Map<*, *>) = Unit
        override fun logResponse(args: Map<*, *>) = Unit
        override fun logError(args: Map<*, *>) = Unit
        override fun clear() = Unit
        override fun launchUi(context: Context) = Unit
        override fun observeCount(): Flow<Int> = flowOf(0)
    }
}
