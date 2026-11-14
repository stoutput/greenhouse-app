package app.greenhouse.greenhouse

import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    private lateinit var preferences: SharedPreferences
    private val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        if (key == "flutter.greenhouse.lock_enabled") runOnUiThread { updatePrivacy() }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val enrollment = getSharedPreferences("greenhouse_biometric_enrollment", MODE_PRIVATE)
        val alias = "greenhouse_biometric_enrollment"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.greenhouse/biometric_enrollment")
            .setMethodCallHandler { call, result ->
                try {
                    val enrolled = call.argument<Boolean>("enrolled") == true
                    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                    when (call.method) {
                        "reset" -> {
                            store.deleteEntry(alias)
                            if (enrolled) {
                                val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                                generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT)
                                    .setBlockModes(KeyProperties.BLOCK_MODE_CBC)
                                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_PKCS7)
                                    .setUserAuthenticationRequired(true)
                                    .setInvalidatedByBiometricEnrollment(true)
                                    .build())
                                generator.generateKey()
                            }
                            if (!enrollment.edit().putBoolean("enrolled", enrolled).commit()) {
                                throw IllegalStateException("Could not save enrollment baseline")
                            }
                            result.success(null)
                        }
                        "hasChanged" -> {
                            val changed = if (!enrollment.contains("enrolled") ||
                                enrollment.getBoolean("enrolled", false) != enrolled) {
                                true
                            } else if (!enrolled) {
                                false
                            } else {
                                val key = store.getKey(alias, null) as? SecretKey
                                if (key == null) true else try {
                                    // Initializing an auth-per-use cipher checks key invalidation
                                    // without decrypting anything or displaying an auth prompt.
                                    Cipher.getInstance("AES/CBC/PKCS7Padding").init(Cipher.ENCRYPT_MODE, key)
                                    false
                                } catch (_: KeyPermanentlyInvalidatedException) {
                                    true
                                } catch (_: UserNotAuthenticatedException) {
                                    false
                                }
                            }
                            result.success(changed)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("enrollment_unavailable", "Could not check biometric enrollment", null)
                }
            }
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
