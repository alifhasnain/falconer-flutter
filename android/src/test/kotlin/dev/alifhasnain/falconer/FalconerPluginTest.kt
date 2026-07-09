package dev.alifhasnain.falconer

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

/*
 * Unit tests of the Kotlin portion of the plugin's channel stubs.
 *
 * Run from the `example/android/` directory with `./gradlew testDebugUnitTest`,
 * or directly from an IDE that supports JUnit such as Android Studio.
 */

internal class FalconerPluginTest {
    @Test
    fun onMethodCall_ping_returnsPong() {
        val plugin = FalconerPlugin()

        val call = MethodCall("ping", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success("pong")
    }

    @Test
    fun onMethodCall_requestNotificationPermission_autoGrantsBelowApi33() {
        // No activity bound and the unit-test SDK_INT is < 33, so the request
        // resolves synchronously through the auto-grant path.
        val plugin = FalconerPlugin()

        val call = MethodCall("requestNotificationPermission", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(true)
    }
}
