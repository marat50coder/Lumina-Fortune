package com.luminafortune.luminagame

import android.app.Activity
import android.content.Intent
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — WebView file-upload bridge for Lumina Fortune.
 *
 * Dependency-free: the site's `<input type="file">` triggers the
 * WebView's file selector, which hops here via a MethodChannel
 * and returns the picked `content://` URIs back to Dart. No
 * `file_picker` dependency is required (see pitfalls doc §1 —
 * file_picker 10.x drags its own KGP that collides with Flutter's
 * built-in Kotlin support).
 *
 * Channel name is project-unique and MUST stay in sync with
 * `lib/prism/screens/web_shell.dart` → `_uploadBridge`.
 */
class MainActivity : FlutterActivity() {

    private val bridgeChannel = "lumina.prism/upload_bridge"
    private val chooserToken = 0x4C46
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bridgeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val multi = call.argument<Boolean>("multi") ?: false
                        val mimes = call.argument<List<String>>("mimes")
                            ?: emptyList()
                        launchChooser(multi, mimes, result)
                    }
                    // WebShell-only: IME overlays the window so Chromium
                    // shrinks visualViewport and JS can lift the field.
                    // Do NOT set this in onCreate — ColorOS 15 then
                    // freezes the first Flutter frame at 0×0.
                    "ime_overlay" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        WindowCompat.setDecorFitsSystemWindows(window, !on)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchChooser(
        multi: Boolean,
        mimes: List<String>,
        result: MethodChannel.Result,
    ) {
        // Resolve any orphaned prior request before starting new one.
        pendingResult?.success(emptyList<String>())
        pendingResult = result

        val validMimes = mimes.filter { it.contains("/") }
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multi)
            when {
                validMimes.isEmpty() -> type = "*/*"
                validMimes.size == 1 -> type = validMimes[0]
                else -> {
                    type = "*/*"
                    putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        validMimes.toTypedArray(),
                    )
                }
            }
        }

        try {
            startActivityForResult(
                Intent.createChooser(intent, null),
                chooserToken,
            )
        } catch (e: Exception) {
            pendingResult = null
            result.success(emptyList<String>())
        }
    }

    /**
     * Warm-click on the OneLink URL delivers a fresh VIEW intent
     * to the already-running singleTop Activity. Flutter's default
     * `onNewIntent` forwards it to plugins, but only if we first
     * call `setIntent(intent)` on ourselves — otherwise the
     * AppsFlyer plugin's ActivityAware wrapper keeps re-reading
     * the stale launch intent and never surfaces the UDL. This
     * override is intentional; do not delete it.
     */
    override fun onNewIntent(intent: Intent) {
        setIntent(intent)
        super.onNewIntent(intent)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != chooserToken) return

        val result = pendingResult
        pendingResult = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<String>())
            return
        }

        val uris = ArrayList<String>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) {
                uris.add(clip.getItemAt(i).uri.toString())
            }
        } else {
            data.data?.let { uris.add(it.toString()) }
        }
        result.success(uris)
    }
}
