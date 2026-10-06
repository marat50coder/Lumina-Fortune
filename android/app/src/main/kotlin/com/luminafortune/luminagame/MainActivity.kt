package com.luminafortune.luminagame

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebSettings
import androidx.core.view.WindowCompat
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

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
    private val referrerTag = "LF/REF"
    private val intentTag = "LF/INTENT"
    private var pendingResult: MethodChannel.Result? = null
    private var referrerClient: InstallReferrerClient? = null
    @Volatile private var referrerDone = false
    @Volatile private var cachedReferrer: String? = null
    private var referrerAttempts = 0
    private val clueWaiters = ArrayList<MethodChannel.Result>()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(intentTag, "onCreate data=${intent?.dataString} extras=${intent?.extras?.keySet()}")
        // Towerbound: content extends under the cutout so the
        // WebView gets its final box in one pass on rotation.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        warmReferrer()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Towerbound: one insets apply after the physical turn,
        // instead of several intermediate frames.
        val root = window.decorView
        root.requestApplyInsets()
        root.requestLayout()
    }

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
                    // Launch URL (OneLink VIEW intent) plus the Play
                    // install referrer. Conversion data can still say
                    // Organic after a real click; these two strings
                    // are the click itself.
                    "launch_clues" -> deliverClues(result)
                    // Same-window hops: the Flutter plugin turns
                    // setSupportMultipleWindows on and then drops the
                    // first window.open / target=_blank click.
                    "tune_webview" -> {
                        val id = call.argument<Number>("id")?.toLong()
                        if (id == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val webView = WebViewFlutterAndroidExternalApi.getWebView(
                            flutterEngine,
                            id,
                        )
                        if (webView == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        @Suppress("DEPRECATION")
                        webView.settings.apply {
                            javaScriptEnabled = true
                            javaScriptCanOpenWindowsAutomatically = true
                            setSupportMultipleWindows(false)
                            domStorageEnabled = true
                            databaseEnabled = true
                            setGeolocationEnabled(true)
                            mixedContentMode =
                                WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                            mediaPlaybackRequiresUserGesture = false
                            // Honor the site's viewport in one layout.
                            // Overview mode scales the old page into the
                            // new size, which reads as a stretch + zoom.
                            useWideViewPort = true
                            loadWithOverviewMode = false
                            setSupportZoom(false)
                            builtInZoomControls = false
                            displayZoomControls = false
                            textZoom = 100
                        }
                        CookieManager.getInstance().apply {
                            setAcceptCookie(true)
                            setAcceptThirdPartyCookies(webView, true)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun warmReferrer() {
        Log.d(referrerTag,
            "warm.attempt=$referrerAttempts done=$referrerDone " +
                "cached.len=${cachedReferrer?.length ?: 0} " +
                "clientAttached=${referrerClient != null}")
        // Cached OK → nothing to do.
        if (!cachedReferrer.isNullOrEmpty()) return
        // Bail after a few attempts so we do not hammer Play
        // Services on devices where it is genuinely missing. The
        // Dart side falls back to AppsFlyer's own retry anyway.
        if (referrerAttempts >= 6) {
            referrerDone = true
            return
        }
        if (referrerClient != null) return
        referrerAttempts++
        val client = InstallReferrerClient.newBuilder(this).build()
        referrerClient = client
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    var value: String? = null
                    var beginTs = 0L
                    var installTs = 0L
                    if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                        try {
                            val d = client.installReferrer
                            value = d.installReferrer
                            beginTs = d.referrerClickTimestampSeconds
                            installTs = d.installBeginTimestampSeconds
                        } catch (t: Throwable) {
                            Log.w(referrerTag, "read failed: ${t.message}")
                        }
                    }
                    Log.d(referrerTag,
                        "setup rc=$responseCode value=\"$value\" " +
                            "click=$beginTs install=$installTs " +
                            "attempt=$referrerAttempts")
                    if (!value.isNullOrEmpty()) {
                        cachedReferrer = value
                        referrerDone = true
                    }
                    try {
                        client.endConnection()
                    } catch (_: Throwable) {}
                    referrerClient = null
                    if (value.isNullOrEmpty() && referrerAttempts < 6) {
                        mainHandler.postDelayed({ warmReferrer() }, 700L * referrerAttempts)
                    } else {
                        referrerDone = true
                    }
                    drainWaiters()
                }

                override fun onInstallReferrerServiceDisconnected() {
                    Log.w(referrerTag, "service disconnected")
                    referrerClient = null
                    if (cachedReferrer.isNullOrEmpty() && referrerAttempts < 6) {
                        mainHandler.postDelayed({ warmReferrer() }, 700L * referrerAttempts)
                    }
                }
            })
        } catch (t: Throwable) {
            Log.w(referrerTag, "connect failed: ${t.message}")
            referrerClient = null
            if (referrerAttempts >= 6) {
                referrerDone = true
                drainWaiters()
            }
        }
    }

    private fun deliverClues(result: MethodChannel.Result) {
        // Fast path: we already have a real referrer.
        if (!cachedReferrer.isNullOrEmpty()) {
            result.success(clueMap())
            return
        }
        // No cached referrer yet. If the offline first boot burned
        // through the retry budget while Play Services was down,
        // reset the fatigue guard so this Dart-side caller (typically
        // fired right after the user comes back online) gets a real
        // second window for the referrer to arrive, instead of the
        // stale "gave up" answer.
        if (referrerDone) {
            referrerDone = false
            referrerAttempts = 0
        }
        clueWaiters.add(result)
        warmReferrer()
        // 2500 ms is enough for a normal install: Play's referrer
        // service answers in well under 1 s when Play Services is
        // healthy. A longer wait just idled the warmup screen —
        // the Dart side has its own retry if the first poll came
        // back empty.
        mainHandler.postDelayed({
            if (clueWaiters.remove(result)) {
                result.success(clueMap())
            }
        }, 2500)
    }

    private fun drainWaiters() {
        if (clueWaiters.isEmpty()) return
        val snapshot = ArrayList(clueWaiters)
        clueWaiters.clear()
        val map = clueMap()
        for (r in snapshot) {
            try {
                r.success(map)
            } catch (_: Throwable) {}
        }
    }

    private fun clueMap(): Map<String, String?> {
        val map = mapOf(
            "url" to intent?.dataString,
            "referrer" to cachedReferrer,
        )
        Log.d(referrerTag,
            "reply url=${map["url"]} " +
                "referrer=${map["referrer"]} " +
                "done=$referrerDone " +
                "waiters=${clueWaiters.size}")
        return map
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
        Log.d(intentTag, "onNewIntent data=${intent.dataString}")
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
