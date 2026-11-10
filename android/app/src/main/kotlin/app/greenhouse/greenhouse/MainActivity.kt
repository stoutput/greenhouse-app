package app.greenhouse.greenhouse

import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    private lateinit var preferences: SharedPreferences
    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "flutter.greenhouse.lock_enabled") runOnUiThread { updatePrivacy() }
    }

    private fun updatePrivacy() {
        val enabled = preferences.getBoolean("flutter.greenhouse.lock_enabled", true)
        if (Build.VERSION.SDK_INT >= 33) {
            setRecentsScreenshotEnabled(!enabled)
        }
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferences = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        preferences.registerOnSharedPreferenceChangeListener(listener)
        updatePrivacy()
    }

    override fun onDestroy() {
        preferences.unregisterOnSharedPreferenceChangeListener(listener)
        super.onDestroy()
    }
}
