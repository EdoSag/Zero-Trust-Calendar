package dev.sagron.zerotrustcalendar

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity, not FlutterActivity: the biometric prompt
 * (local_auth) needs a FragmentActivity.
 *
 * `zt_calendar/apps` opens a sibling Zero-Trust app (ZT Notes for a linked
 * note, say), or its Play Store page when it isn't installed.
 */
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zt_calendar/apps")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg == null || !pkg.startsWith("dev.sagron.")) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val launch = packageManager.getLaunchIntentForPackage(pkg)
                        if (launch != null) {
                            startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } else {
                            try {
                                startActivity(
                                    Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg"))
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                                )
                            } catch (e: Exception) {
                                startActivity(
                                    Intent(
                                        Intent.ACTION_VIEW,
                                        Uri.parse("https://play.google.com/store/apps/details?id=$pkg"),
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                                )
                            }
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
