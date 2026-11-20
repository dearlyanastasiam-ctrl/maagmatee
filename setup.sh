# Jalankan SEKALI dari folder maagmate (yang ada pubspec.yaml).
$ErrorActionPreference = 'Stop'
if (-not (Test-Path .\pubspec.yaml)) { throw 'Jalankan dari folder yang berisi pubspec.yaml' }

# Simpan kode kita, karena flutter create bisa menimpa file bawaan
$bk = Join-Path $env:TEMP 'maagmate_bk'
Remove-Item $bk -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $bk | Out-Null
Copy-Item lib $bk -Recurse
Copy-Item pubspec.yaml $bk

flutter create --org id.maagmate --project-name maagmate --platforms android .

# Kembalikan kode kita
Remove-Item lib -Recurse -Force
Copy-Item "$bk\lib" lib -Recurse
Copy-Item "$bk\pubspec.yaml" pubspec.yaml -Force
# Tes bawaan merujuk MyApp yang sudah tidak ada
Remove-Item test -Recurse -Force -ErrorAction SilentlyContinue

$utf8 = New-Object System.Text.UTF8Encoding($false)

# Izin Android + alarm layar penuh
$f = (Resolve-Path 'android\app\src\main\AndroidManifest.xml').Path
$m = [System.IO.File]::ReadAllText($f)
if ($m -notmatch 'USE_FULL_SCREEN_INTENT') {
  $perm = @'
<uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <application
'@
  if ($m -match 'POST_NOTIFICATIONS') {
    # setup versi lama sudah menambah 3 izin pertama; tambahkan sisanya saja
    $perm = @'
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <application
'@
  }
  $m = ([regex]'<application').Replace($m, $perm, 1)
}
if ($m -notmatch 'android.permission.CAMERA') {
  $cam = @'
<uses-permission android:name="android.permission.CAMERA"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    <application
'@
  $m = ([regex]'<application').Replace($m, $cam, 1)
}
if ($m -notmatch 'showWhenLocked') {
  $m = ([regex]'<activity').Replace($m, '<activity android:showWhenLocked="true" android:turnScreenOn="true"', 1)
}
if ($m -notmatch 'ScheduledNotificationReceiver') {
  $rcv = @'
<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>
'@
  $m = $m.Replace('</application>', $rcv)
}
$m = $m -replace 'android:label="maagmate"', 'android:label="MaagMate"'
[System.IO.File]::WriteAllText($f, $m, $utf8)

# Desugaring
if (Test-Path 'android\app\build.gradle.kts') {
  $g = (Resolve-Path 'android\app\build.gradle.kts').Path
  $t = [System.IO.File]::ReadAllText($g)
  if ($t -notmatch 'isCoreLibraryDesugaringEnabled') {
    $t = ([regex]'compileOptions \{').Replace($t, "compileOptions {`n        isCoreLibraryDesugaringEnabled = true", 1)
    $t += "`ndependencies {`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")`n}`n"
    [System.IO.File]::WriteAllText($g, $t, $utf8)
  }
} else {
  $g = (Resolve-Path 'android\app\build.gradle').Path
  $t = [System.IO.File]::ReadAllText($g)
  if ($t -notmatch 'coreLibraryDesugaringEnabled') {
    $t = ([regex]'compileOptions \{').Replace($t, "compileOptions {`n        coreLibraryDesugaringEnabled true", 1)
    $t += "`ndependencies {`n    coreLibraryDesugaring `"com.android.tools:desugar_jdk_libs:2.1.4`"`n}`n"
    [System.IO.File]::WriteAllText($g, $t, $utf8)
  }
}

flutter pub get
# Ikon app + splash screen
dart run flutter_launcher_icons
dart run flutter_native_splash:create
Write-Host 'Selesai. Build: flutter build apk --release --dart-define=GEMINI_API_KEY=KUNCI_KAMU'