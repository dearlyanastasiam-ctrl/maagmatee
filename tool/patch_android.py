"""Menambah izin, receiver alarm, label, dan desugaring ke proyek Android hasil `flutter create`.
Sama fungsinya dengan setup.sh, tetapi untuk dijalankan otomatis di GitHub Actions."""
import pathlib
import re

root = pathlib.Path('android/app')

# ---------------------------------------------------------------- manifest
mf = root / 'src/main/AndroidManifest.xml'
m = mf.read_text(encoding='utf-8')

for p in ['INTERNET', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED',
          'USE_FULL_SCREEN_INTENT', 'SCHEDULE_EXACT_ALARM', 'USE_EXACT_ALARM', 'VIBRATE',
          'WAKE_LOCK', 'CAMERA']:
    if f'android.permission.{p}' not in m:
        m = m.replace('<application',
                      f'<uses-permission android:name="android.permission.{p}"/>\n    <application', 1)

if 'android.hardware.camera' not in m:
    m = m.replace('<application',
                  '<uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application', 1)

if 'showWhenLocked' not in m:
    m = m.replace('<activity',
                  '<activity android:showWhenLocked="true" android:turnScreenOn="true"', 1)

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
print('Android dipatch.')