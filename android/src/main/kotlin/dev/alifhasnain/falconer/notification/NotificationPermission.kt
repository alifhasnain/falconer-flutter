package dev.alifhasnain.falconer.notification

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

/**
 * Requests the Android 13+ `POST_NOTIFICATIONS` runtime permission.
 *
 * A plugin cannot prompt without a foreground Activity, so this relies on the
 * [ActivityPluginBinding] captured via `ActivityAware`. Contract:
 * - pre-33: auto-granted → `true`.
 * - no foreground Activity: `false` (the host should call this from a screen).
 * - 33+: shows the system dialog and reports the grant result.
 */
class NotificationPermission : PluginRegistry.RequestPermissionsResultListener {

    private var pending: ((Boolean) -> Unit)? = null

    fun request(binding: ActivityPluginBinding?, onResult: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            onResult(true)
            return
        }
        val activity = binding?.activity
        if (activity == null) {
            onResult(false)
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            onResult(true)
            return
        }
        pending = onResult
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending?.invoke(granted)
        pending = null
        return true
    }

    companion object {
        private const val REQUEST_CODE = 0xFA1D
    }
}
