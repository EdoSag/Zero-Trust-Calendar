package dev.sagron.zerotrustcalendar

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import dev.sagron.zerotrustcalendar.phone.PhoneCalendar
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * FlutterFragmentActivity, not FlutterActivity: the biometric prompt
 * (local_auth) needs a FragmentActivity.
 *
 * Channels:
 * - `zt_calendar/apps` opens a sibling Zero-Trust app (or its store page),
 *   hands an invitation file to the mail app, and logs an event's time in
 *   ZT Time (see [ZtLinks]).
 * - `zt_calendar/files` holds .ics files, webcal links, shared calendar
 *   invites and ZT Time's "open this event" other apps opened Calendar
 *   with, until the unlocked app takes them.
 * - `zt_calendar/phone_calendar` copies events into Android's calendar,
 *   only for calendars the user turned on (see PhoneCalendar).
 */
class MainActivity : FlutterFragmentActivity() {
    private var files: MethodChannel? = null
    private val pending = mutableListOf<Map<String, Any?>>()
    private var permissionResult: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    /** Waiting for ZT Time's answer to "Log as time entry" (see [ZtLinks]). */
    private var trackResult: MethodChannel.Result? = null

    /** ZT Keyboard is waiting for the user to pick a text here (see [TextPick]). */
    private var pickingText = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (TextPick.isPick(intent)) {
            // Only another Zero-Trust app may ask; anyone else gets nothing.
            if (TextPick.callerAllowed(this)) pickingText = true else TextPick.answer(this, null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "zt_calendar/text_pick").setMethodCallHandler { call, result ->
            when (call.method) {
                // configureFlutterEngine runs inside super.onCreate, before pickingText is
                // set, so the question is answered from the intent and the caller check.
                "isPick" -> result.success(TextPick.isPick(intent) && TextPick.callerAllowed(this))
                // ZT Time asks for an event, not only a text (WANT_ITEM).
                "wantsItem" -> result.success(TextPick.isPick(intent) && ZtLinks.wantsItem(intent))
                "finish" -> {
                    // Answers only the screen the keyboard itself opened.
                    if (pickingText) {
                        pickingText = false
                        TextPick.answer(this, call.argument<String>("text"), call.argument<Map<String, Any?>>("item"))
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "zt_calendar/apps").setMethodCallHandler { call, result ->
            when (call.method) {
                "timeInstalled" -> result.success(ZtLinks.timeInstalled(this))
                "trackTime" -> {
                    if (trackResult != null) {
                        result.success(null)
                    } else if (ZtLinks.trackTime(
                            this,
                            itemId = call.argument<String>("id") ?: "",
                            title = call.argument<String>("title") ?: "",
                            startMs = call.argument<Number>("startMs")?.toLong(),
                            endMs = call.argument<Number>("endMs")?.toLong(),
                        )
                    ) {
                        // Answered in onActivityResult: true saved, false cancelled.
                        trackResult = result
                    } else {
                        result.success(null)
                    }
                }
                "open" -> result.success(openApp(call.argument<String>("package")))
                "sendInvite" -> {
                    sendInvite(
                        path = call.argument<String>("path")!!,
                        emails = call.argument<List<String>>("emails") ?: emptyList(),
                        subject = call.argument<String>("subject") ?: "",
                        text = call.argument<String>("text") ?: "",
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        files = MethodChannel(messenger, "zt_calendar/files").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePending" -> {
                        val out = ArrayList(pending)
                        pending.clear()
                        result.success(out)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(messenger, "zt_calendar/phone_calendar").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasCalendarPermission())
                "requestPermission" -> {
                    if (hasCalendarPermission()) {
                        result.success(true)
                    } else {
                        permissionResult = result
                        requestPermissions(
                            arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
                            REQUEST_CALENDAR,
                        )
                    }
                }
                "sync" -> {
                    if (!hasCalendarPermission()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    @Suppress("UNCHECKED_CAST")
                    val calendars = call.argument<List<Map<String, Any?>>>("calendars") ?: emptyList()
                    Thread {
                        val ok = try {
                            PhoneCalendar(contentResolver).sync(calendars)
                            true
                        } catch (e: Exception) {
                            false
                        }
                        main.post { result.success(ok) }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // A pick request is only honoured when it opens its own screen (onCreate), where
        // Android tells who is asking.
        if (TextPick.isPick(intent)) return
        setIntent(intent)
        handleIntent(intent)
    }

    @Deprecated("Deprecated in Android, still the simplest hook here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == ZtLinks.REQUEST_TRACK_TIME) {
            trackResult?.success(resultCode == RESULT_OK)
            trackResult = null
        }
    }

    @Deprecated("Deprecated in Android, still the simplest hook here")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CALENDAR) {
            permissionResult?.success(hasCalendarPermission())
            permissionResult = null
        }
    }

    private fun hasCalendarPermission() =
        checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

    /** Queues an opened or shared .ics file, or a webcal:// link. */
    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        // ZT Time opens an event it is linked to; shown once unlocked.
        ZtLinks.openItemId(intent)?.let { id ->
            intent.action = null
            pending.add(mapOf("open" to id))
            files?.invokeMethod("filesArrived", null)
            return
        }
        val uri: Uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            else -> null
        } ?: return
        val scheme = uri.scheme?.lowercase()
        val item: Map<String, Any?>? = when (scheme) {
            "webcal", "webcals" -> mapOf("url" to "https://" + uri.toString().substringAfter("://"))
            // A shared calendar invite; the app checks it once unlocked.
            "https" -> if (uri.host == "zerotrust.bz" && (uri.path ?: "").startsWith("/join")) {
                mapOf("invite" to uri.toString())
            } else {
                null
            }
            "content", "file" -> try {
                contentResolver.openInputStream(uri)?.use { input ->
                    // Calendar files are small; refuse anything huge.
                    val bytes = input.readBytes()
                    if (bytes.size > 10 * 1024 * 1024) null else mapOf("name" to displayName(uri), "bytes" to bytes)
                }
            } catch (e: Exception) {
                null
            }
            else -> null
        }
        if (item == null) return
        // Taken once: rotating the screen must not import it again.
        intent.action = null
        pending.add(item)
        files?.invokeMethod("filesArrived", null)
    }

    private fun displayName(uri: Uri): String {
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) return c.getString(0) ?: "event.ics"
            }
        } catch (e: Exception) {
            // Fall through.
        }
        return uri.lastPathSegment ?: "event.ics"
    }

    private fun openApp(pkg: String?): Boolean {
        if (pkg == null || !pkg.startsWith("dev.sagron.")) return false
        val launch = packageManager.getLaunchIntentForPackage(pkg)
        if (launch != null) {
            startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return true
        }
        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (e: Exception) {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$pkg"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
        return false
    }

    /** Opens the mail app with the guests, subject, text and the .ics file. */
    private fun sendInvite(path: String, emails: List<String>, subject: String, text: String) {
        val file = File(path)
        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/calendar"
            putExtra(Intent.EXTRA_EMAIL, emails.toTypedArray())
            putExtra(Intent.EXTRA_SUBJECT, subject)
            putExtra(Intent.EXTRA_TEXT, text)
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(send, "Send invitation"))
    }

    companion object {
        private const val REQUEST_CALENDAR = 4107
    }
}
