"""Menambah izin, receiver alarm, label, dan desugaring ke proyek Android hasil `flutter create`.
Sama fungsinya dengan setup.sh, tetapi untuk dijalankan otomatis di GitHub Actions."""
import pathlib
import re

MAIN_KT = r'''package id.maagmate.maagmate

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private fun canOverlay(): Boolean =
        Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "maagmate/launch")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val at = (call.argument<Number>("at") ?: 0L).toLong()
                        val daily = call.argument<Boolean>("daily") ?: false
                        AlarmLaunch.schedule(this, id, at, daily)
                        result.success(null)
                    }
                    "cancel" -> {
                        AlarmLaunch.cancel(this, call.argument<Int>("id") ?: 0)
                        result.success(null)
                    }
                    "canOverlay" -> result.success(canOverlay())
                    "requestOverlay" -> {
                        if (!canOverlay()) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
'''
RECV_KT = r'''package id.maagmate.maagmate

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings

/** Menjadwalkan peluncur alarm (membuka MaagMate saat alarm berbunyi). */
object AlarmLaunch {
    private const val PREFS = "maagmate_alarms"
    private const val ACTION = "id.maagmate.ALARM_FIRE"
    private const val DAY = 24L * 60 * 60 * 1000

    private fun fire(ctx: Context, id: Int): PendingIntent {
        val i = Intent(ctx, AlarmReceiver::class.java).setAction(ACTION).putExtra("id", id)
        return PendingIntent.getBroadcast(
            ctx, id, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun schedule(ctx: Context, id: Int, at: Long, daily: Boolean) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val show = PendingIntent.getActivity(
            ctx, id, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), fire(ctx, id))
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(id.toString(), "$at|$daily").apply()
    }

    fun cancel(ctx: Context, id: Int) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(fire(ctx, id))
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(id.toString()).apply()
    }

    /** Dipanggil setelah alarm berbunyi: jadwalkan besok (alarm harian) atau hapus. */
    fun rearm(ctx: Context, id: Int) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val parts = (prefs.getString(id.toString(), null) ?: return).split("|")
        val at = parts[0].toLongOrNull() ?: return
        if (parts.getOrNull(1) == "true") {
            var next = at + DAY
            while (next <= System.currentTimeMillis()) next += DAY
            schedule(ctx, id, next, true)
        } else {
            prefs.edit().remove(id.toString()).apply()
        }
    }

    /** Setelah HP restart / app diperbarui. */
    fun restore(ctx: Context) {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        for ((key, value) in prefs.all) {
            val id = key.toIntOrNull() ?: continue
            val parts = (value as? String)?.split("|") ?: continue
            var at = parts[0].toLongOrNull() ?: continue
            val daily = parts.getOrNull(1) == "true"
            if (at <= System.currentTimeMillis()) {
                if (!daily) {
                    prefs.edit().remove(key).apply()
                    continue
                }
                while (at <= System.currentTimeMillis()) at += DAY
            }
            schedule(ctx, id, at, daily)
        }
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action != "id.maagmate.ALARM_FIRE") {
            AlarmLaunch.restore(ctx) // BOOT_COMPLETED / MY_PACKAGE_REPLACED
            return
        }
        AlarmLaunch.rearm(ctx, intent.getIntExtra("id", 0))
        // Android hanya mengizinkan app membuka layar dari latar bila diberi
        // izin "Tampil di atas aplikasi lain". Tanpa izin: cukup notifikasi.
        if (Build.VERSION.SDK_INT >= 23 && !Settings.canDrawOverlays(ctx)) return
        try {
            ctx.startActivity(
                Intent(ctx, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
            )
        } catch (_: Exception) {
        }
    }
}
'''

root = pathlib.Path('android/app')

# ---------------------------------------------------------------- manifest
mf = root / 'src/main/AndroidManifest.xml'
m = mf.read_text(encoding='utf-8')

for p in ['INTERNET', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED',
          'USE_FULL_SCREEN_INTENT', 'SCHEDULE_EXACT_ALARM', 'USE_EXACT_ALARM', 'VIBRATE',
          'WAKE_LOCK', 'CAMERA', 'SYSTEM_ALERT_WINDOW']:
    if f'android.permission.{p}' not in m:
        m = m.replace('<application',
                      f'<uses-permission android:name="android.permission.{p}"/>\n    <application', 1)

if 'android.hardware.camera' not in m:
    m = m.replace('<application',
                  '<uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application', 1)

if 'showWhenLocked' not in m:
    m = m.replace('<activity',
                  '<activity android:showWhenLocked="true" android:turnScreenOn="true"', 1)

if 'id.maagmate.maagmate.AlarmReceiver' not in m and '.AlarmReceiver' not in m:
    m = m.replace('</application>', '''<receiver android:name=".AlarmReceiver" android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>''', 1)

if 'ScheduledNotificationReceiver' not in m:
    rcv = '''<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>'''
    m = m.replace('</application>', rcv, 1)

m = re.sub(r'android:label="[^"]*"', 'android:label="MaagMate"', m, count=1)
mf.write_text(m, encoding='utf-8')

# ----------------------------------------------------------------- gradle
kts = root / 'build.gradle.kts'
groovy = root / 'build.gradle'
if kts.exists():
    t = kts.read_text(encoding='utf-8')
    if 'isCoreLibraryDesugaringEnabled' not in t:
        t = re.sub(r'compileOptions\s*\{',
                   'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', t, count=1)
        t += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        kts.write_text(t, encoding='utf-8')
elif groovy.exists():
    t = groovy.read_text(encoding='utf-8')
    if 'coreLibraryDesugaringEnabled' not in t:
        t = re.sub(r'compileOptions\s*\{',
                   'compileOptions {\n        coreLibraryDesugaringEnabled true', t, count=1)
        t += '\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n}\n'
        groovy.write_text(t, encoding='utf-8')
else:
    raise SystemExit('build.gradle tidak ditemukan')
# Matikan R8/shrink di build release: kalau aktif, plugin notifikasi (Gson)
# rusak di APK release dan alarm gagal dijadwalkan tanpa pesan error.
def _no_shrink(path, kts_syntax):
    t = path.read_text(encoding='utf-8')
    if 'MAAGMATE_NO_SHRINK' in t:
        return
    line = ('isMinifyEnabled = false\n            isShrinkResources = false'
            if kts_syntax else
            'minifyEnabled false\n            shrinkResources false')
    t2 = re.sub(r'release\s*\{', 'release {\n            // MAAGMATE_NO_SHRINK\n            ' + line, t, count=1)
    path.write_text(t2, encoding='utf-8')

if kts.exists():
    _no_shrink(kts, True)
elif groovy.exists():
    _no_shrink(groovy, False)
# ------------------------------------------------------------------ native
# Peluncur alarm: membuka MaagMate (lalu kamera) saat alarm berbunyi.
kdir = root / 'src/main/kotlin/id/maagmate/maagmate'
kdir.mkdir(parents=True, exist_ok=True)
(kdir / 'MainActivity.kt').write_text(MAIN_KT, encoding='utf-8')
(kdir / 'AlarmReceiver.kt').write_text(RECV_KT, encoding='utf-8')
print('Android dipatch.')