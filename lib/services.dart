import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'secrets.dart';

/// Naik setiap alarm dibuka/diketuk; HomeShell lalu menampilkan layar alarm.
final ValueNotifier<int> ringTick = ValueNotifier<int>(0);
int ringId = 0;

class Store {
  static Future<List<MealLog>> logs() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('logs');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => MealLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveLogs(List<MealLog> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('logs', jsonEncode(l.map((e) => e.toJson()).toList()));
  }

  static Future<List<Reminder>> reminders() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('reminders');
    if (raw == null) {
      return [
        Reminder(id: 1, hour: 7, minute: 0, label: 'Sarapan'),
        Reminder(id: 2, hour: 12, minute: 0, label: 'Makan siang'),
        Reminder(id: 3, hour: 19, minute: 0, label: 'Makan malam'),
      ];
    }
    return (jsonDecode(raw) as List)
        .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<bool> onboarded() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('onboarded') ?? false;
  }

  static Future<void> setOnboarded() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('onboarded', true);
  }

  /// Simpan foto makanan: path file (Android) atau data base64 kecil (web).
  /// Mengembalikan null bila gagal.
  static Future<String?> savePhoto(XFile x) async {
    try {
      if (kIsWeb) {
        // Web: kecilkan lalu simpan sebagai teks base64 di dalam catatan.
        final src = img.decodeImage(await x.readAsBytes());
        if (src == null) return null;
        final small = img.copyResize(src, width: 320);
        return 'data:image/jpeg;base64,${base64Encode(img.encodeJpg(small, quality: 70))}';
      }
      final dir = Directory(
          '${(await getApplicationDocumentsDirectory()).path}/meal_photos');
      await dir.create(recursive: true);
      final dest = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(x.path).copy(dest);
      return dest;
    } catch (_) {
      return null;
    }
  }

  static Future<void> deletePhoto(String? path) async {
    if (path == null || kIsWeb) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  /// Hapus semua catatan makan beserta fotonya (jadwal alarm & lagu tidak ikut dihapus).
  static Future<void> clearLogs() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('logs');
    if (!kIsWeb) {
      try {
        final d = Directory(
            '${(await getApplicationDocumentsDirectory()).path}/meal_photos');
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<void> saveReminders(List<Reminder> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'reminders', jsonEncode(l.map((e) => e.toJson()).toList()));
  }
}

class Notif {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const channelId = 'meal_alarm';
  static const quietId = 'meal_alarm_quiet';

  static Future<void> init({bool askPermissions = true}) async {
    if (kIsWeb) return; // alarm hanya untuk Android
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        ringId = int.tryParse(r.payload ?? '') ?? 0;
        ringTick.value++;
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      ringId = int.tryParse(launch?.notificationResponse?.payload ?? '') ?? 0;
      ringTick.value++;
    }
    if (askPermissions) await requestPermissions();
  }

  /// Minta izin notifikasi & alarm (dipanggil setelah onboarding pada pemakaian pertama).
  static Future<void> requestPermissions() async {
    if (kIsWeb) return;
    final a = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await a?.requestNotificationsPermission();
    await a?.requestExactAlarmsPermission();
  }

  static tz.TZDateTime _next(int h, int m) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (d.isBefore(now)) d = d.add(const Duration(days: 1));
    return d;
  }

  // Alarm: bunyi berulang (insistent), tidak bisa di-swipe, membuka layar penuh.
  static NotificationDetails _details() => NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Alarm makan',
          channelDescription: 'Alarm yang berhenti setelah foto makanan',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          visibility: NotificationVisibility.public,
          playSound: true,
          sound: const UriAndroidNotificationSound(
              'content://settings/system/alarm_alert'),
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 800, 500, 800, 500]),
          additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
        ),
      );

  /// Jadwalkan notifikasi. Bila izin alarm persis (exact) belum diberikan,
  /// pakai jadwal tidak-persis supaya alarm tetap bunyi (bisa telat beberapa menit).
  static Future<void> _schedule(int id, String title, String body,
      tz.TZDateTime when, String payload,
      {DateTimeComponents? repeat}) async {
    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          _details(),
          payload: payload,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: repeat,
        );
    try {
      await go(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      if ((e.code).toLowerCase().contains('exact_alarms_not_permitted')) {
        await go(AndroidScheduleMode.inexactAllowWhileIdle);
      } else {
        rethrow;
      }
    }
  }

  static Future<void> apply(Reminder r) async {
    if (kIsWeb) return;
    await _plugin.cancel(r.id);
    await AlarmLaunch.cancel(r.id);
    if (!r.on) return;
    await AlarmLaunch.schedule(r.id, _next(r.hour, r.minute), daily: true);
    await _schedule(
      r.id,
      'Waktunya ${r.label}',
      'Buka & foto makananmu untuk mematikan alarm.',
      _next(r.hour, r.minute),
      r.id.toString(),
      repeat: DateTimeComponents.time,
    );
  }

  /// Alarm uji coba: bunyi 5 detik lagi. Mengembalikan null bila berhasil,
  /// atau teks penyebab bila gagal (supaya terlihat di layar).
  static Future<String?> test() async {
    if (kIsWeb) return null;
    try {
      final a = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      var enabled = await a?.areNotificationsEnabled();
      if (enabled == false) {
        await a?.requestNotificationsPermission();
        enabled = await a?.areNotificationsEnabled();
      }
      if (enabled == false) {
        return 'Izin notifikasi MATI. Buka Pengaturan > Aplikasi > MaagMate > Notifikasi, lalu aktifkan.';
      }
      final when = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5));
      await AlarmLaunch.schedule(999, when);
      await _schedule(
        999,
        'Alarm uji coba',
        'Foto makananmu untuk mematikan alarm.',
        when,
        '999',
      );
      return null;
    } catch (e) {
      return 'Gagal menjadwalkan alarm: $e';
    }
  }

  /// Id alarm yang sedang berbunyi (null bila tidak ada).
  static Future<int?> activeAlarmId() async {
    if (kIsWeb) return null;
    try {
      final l = await _plugin.getActiveNotifications();
      for (final n in l) {
        if ((n.channelId == channelId || n.channelId == quietId) && n.id != null) {
          return n.id;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Dipanggil saat layar alarm sudah tampil: bunyi bawaan notifikasi dihentikan
  /// (diganti notifikasi senyap dengan id sama) supaya lagu pilihan tidak
  /// bertabrakan. Jadwal alarm besok tidak ikut terhapus.
  static Future<void> quiet(int id) async {
    if (kIsWeb) return;
    try {
      await _plugin.show(
        id,
        'Alarm makan berbunyi',
        'Buka & foto makananmu untuk mematikan alarm.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            quietId,
            'Alarm makan (senyap)',
            channelDescription: 'Notifikasi alarm saat layar alarm terbuka',
            importance: Importance.low,
            priority: Priority.low,
            category: AndroidNotificationCategory.alarm,
            ongoing: true,
            autoCancel: false,
            playSound: false,
            enableVibration: false,
            visibility: NotificationVisibility.public,
          ),
        ),
        payload: id.toString(),
      );
    } catch (_) {}
  }

  /// Bunyikan lagi alarm keras (dipakai bila pengguna keluar dari layar alarm
  /// sebelum memfoto makanan). Id sama dengan notifikasi senyap -> menggantikannya.
  static Future<void> loud(int id, String label) async {
    if (kIsWeb) return;
    try {
      await _plugin.show(
        id,
        'Waktunya $label!',
        'Foto makananmu dulu untuk mematikan alarm.',
        _details(),
        payload: id.toString(),
      );
    } catch (_) {}
  }

  /// Matikan alarm (dipanggil HANYA setelah foto makanan), lalu jadwalkan besok.
  static Future<void> stop(int id) async {
    if (kIsWeb) return;
    await _plugin.cancel(id);
    for (final r in await Store.reminders()) {
      if (r.id == id) await apply(r);
    }
  }

  static Future<void> cancel(int id) async {
    if (kIsWeb) return;
    await _plugin.cancel(id);
    await AlarmLaunch.cancel(id);
  }
}

// ============================================================ Lagu alarm
class SoundItem {
  final String id; // 'a:<path asset>' (bawaan) atau 'c:<id>' (milik pengguna)
  final String name;
  final String? path; // file lokal untuk lagu milik pengguna (Android)
  const SoundItem(this.id, this.name, {this.path});
  bool get custom => id.startsWith('c:');
}

class Sounds {
  static const defaultId = 'a:alarm.wav';
  static const builtin = <SoundItem>[
    SoundItem('a:alarm.wav', 'Alarm Klasik'),
    SoundItem('a:sounds/ode_to_joy.wav', 'Ode to Joy'),
    SoundItem('a:sounds/fur_elise.wav', 'Für Elise'),
    SoundItem('a:sounds/twinkle.wav', 'Twinkle Twinkle'),
    SoundItem('a:sounds/lonceng_pagi.wav', 'Lonceng Pagi'),
    SoundItem('a:sounds/beep_digital.wav', 'Beep Digital'),
  ];

  // Di web file tidak bisa disimpan permanen: lagu custom hanya hidup di memori.
  static final Map<String, Uint8List> _webBytes = {};
  static final List<SoundItem> _webItems = [];

  static Future<List<SoundItem>> custom() async {
    if (kIsWeb) return List.of(_webItems);
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('custom_sounds');
    if (raw == null) return [];
    final out = <SoundItem>[];
    for (final e in jsonDecode(raw) as List) {
      final m = e as Map<String, dynamic>;
      final path = m['path'] as String;
      if (File(path).existsSync()) {
        out.add(SoundItem(m['id'] as String, m['name'] as String, path: path));
      }
    }
    return out;
  }

  static Future<void> _saveCustom(List<SoundItem> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'custom_sounds',
        jsonEncode([
          for (final s in l) {'id': s.id, 'name': s.name, 'path': s.path}
        ]));
  }

  static Future<List<SoundItem>> all() async => [...builtin, ...await custom()];

  static Future<SoundItem> selected() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString('alarm_sound') ?? defaultId;
    final l = await all();
    return l.firstWhere((s) => s.id == id, orElse: () => builtin.first);
  }

  static Future<void> select(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('alarm_sound', id);
  }

  static Source source(SoundItem s) {
    if (!s.custom) return AssetSource(s.id.substring(2));
    if (kIsWeb) return BytesSource(_webBytes[s.id]!);
    return DeviceFileSource(s.path!);
  }

  /// Pilih file audio dari HP. Null bila dibatalkan.
  static Future<SoundItem?> addCustom() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.audio, withData: kIsWeb);
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.first;
    if (f.size > 20 * 1024 * 1024) {
      throw Exception('File terlalu besar (maksimal 20 MB).');
    }
    final name = f.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final id = 'c:${DateTime.now().millisecondsSinceEpoch}';
    if (kIsWeb) {
      final b = f.bytes;
      if (b == null) return null;
      final item = SoundItem(id, name);
      _webBytes[id] = b;
      _webItems.add(item);
      return item;
    }
    if (f.path == null) return null;
    final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/sounds');
    await dir.create(recursive: true);
    final dest = '${dir.path}/${id.substring(2)}.${f.extension ?? 'mp3'}';
    await File(f.path!).copy(dest);
    final item = SoundItem(id, name, path: dest);
    await _saveCustom([...await custom(), item]);
    return item;
  }

  static Future<void> removeCustom(String id) async {
    if (kIsWeb) {
      _webItems.removeWhere((s) => s.id == id);
      _webBytes.remove(id);
    } else {
      final l = await custom();
      for (final s in l.where((s) => s.id == id)) {
        try {
          await File(s.path!).delete();
        } catch (_) {}
      }
      await _saveCustom(l.where((s) => s.id != id).toList());
    }
    final p = await SharedPreferences.getInstance();
    if (p.getString('alarm_sound') == id) await p.remove('alarm_sound');
  }
}

class Nutrition {
  // Jalankan dengan: flutter run --dart-define-from-file=env.json
  static const _key =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: kGeminiKey);
  // Model utama + cadangan (semua berstatus Stable di dokumentasi Google,
  // dicek 15 Okt 2026). Bila salah satu sibuk / hilang, otomatis pindah ke
  // berikutnya. Ganti urutannya bila Google merilis model baru.
  static const _model =
      String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.8-flash');
  static const _fallbackModels = [
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
    'gemini-3.1-flash-lite',
  ];

  /// Kode status yang berarti "server sibuk/gangguan sementara".
  static const _busyCodes = {429, 500, 502, 503, 504};

  /// Satu kali kirim ke Gemini. Mengembalikan null bila timeout (boleh dicoba
  /// model lain); tidak ada internet -> langsung melempar pesan Indonesia.
  static Future<http.Response?> _send(String body, String model) async {
    try {
      return await http
          .post(
            Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_key'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return null;
    } catch (_) {
      throw Exception('Tidak ada koneksi internet.');
    }
  }

  /// Perkecil foto (maks 768 px, JPEG 75) supaya upload cepat. Foto kamera
  /// penuh bisa 3-10 MB; untuk menebak makanan 768 px sudah cukup.
  static Future<Uint8List> _shrink(Uint8List bytes) async {
    try {
      return await compute(_shrinkSync, bytes);
    } catch (_) {
      return bytes;
    }
  }

  static Uint8List _shrinkSync(Uint8List bytes) {
    final src = img.decodeImage(bytes);
    if (src == null) return bytes;
    final longest = src.width > src.height ? src.width : src.height;
    final out = longest > 768
        ? img.copyResize(src,
            width: src.width >= src.height ? 768 : null,
            height: src.height > src.width ? 768 : null)
        : src;
    return Uint8List.fromList(img.encodeJpg(out, quality: 75));
  }

  static Future<Estimate> estimate(XFile image) async {
    if (_key.isEmpty) {
      throw Exception('GEMINI_API_KEY belum diisi saat build.');
    }
    final b64 = base64Encode(await _shrink(await image.readAsBytes()));
    const prompt =
        'Kamu ahli gizi. Lihat foto ini. Jawab HANYA JSON: '
        '{"is_food":true/false,"foods":["nama makanan dalam bahasa Indonesia"],'
        '"carbs_g":angka,"protein_g":angka,"fat_g":angka,"kcal":angka}. '
        'Angka adalah perkiraan total untuk porsi yang terlihat. '
        'Jika bukan makanan, is_food=false dan semua angka 0.';
    String bodyFor(bool useThink) => jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': b64}
            }
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'maxOutputTokens': 2048,
        if (useThink) 'thinkingConfig': {'thinkingLevel': 'LOW'}
      }
    });
    var think = true;
    var reqBody = bodyFor(think);

    // Urutan model: yang terakhir berhasil dulu (diingat antar sesi), lalu
    // model utama, lalu cadangan. Tiap model dicoba maksimal 2x. Timeout atau
    // 404 langsung pindah model; 429/5xx dicoba sekali lagi lalu pindah model;
    // error lain (mis. key salah) berhenti dan dilaporkan.
    final prefs = await SharedPreferences.getInstance();
    final lastGood = prefs.getString('ai_model_ok');
    final models = <String>{
      if (lastGood != null && lastGood.isNotEmpty) lastGood,
      _model,
      ..._fallbackModels,
    }.toList();

    http.Response? last;
    outer:
    for (final m in models) {
      for (var i = 1; i <= 2; i++) {
        last = await _send(reqBody, m);
        final c = last?.statusCode;
        if (c == 200) {
          await prefs.setString('ai_model_ok', m);
          break outer;
        }
        if (c == 400 &&
            think &&
            (last?.body.toLowerCase().contains('thinking') ?? false)) {
          // Model ini tidak mendukung level berpikir -> kirim ulang tanpa itu.
          think = false;
          reqBody = bodyFor(false);
          i--;
          continue;
        }
        if (c == null || c == 404) break; // timeout / model tidak ada -> model lain
        if (!_busyCodes.contains(c)) break outer; // error fatal, jangan lanjut
        if (i < 2) await Future.delayed(const Duration(milliseconds: 1500));
      }
    }
    final res = last;
    if (res == null) {
      throw Exception('Koneksi terlalu lambat. Coba lagi.');
    }

    if (res.statusCode == 503 || res.statusCode >= 500) {
      throw Exception('Server AI sedang sibuk. Coba lagi sebentar ya.');
    }
    if (res.statusCode == 404) {
      throw Exception(
          'Model AI tidak ditemukan (404). Build ulang dengan --dart-define=GEMINI_MODEL=<model terbaru>.');
    }
    if (res.statusCode == 429) {
      throw Exception('Kuota AI sedang habis. Tunggu sebentar lalu coba lagi.');
    }
    if (res.statusCode != 200) {
      var detail = '';
      try {
        detail = (jsonDecode(res.body)['error']['message'] ?? '').toString();
      } catch (_) {}
      if (detail.length > 160) detail = '${detail.substring(0, 160)}...';
      throw Exception(
          'Gagal menghubungi AI (${res.statusCode}).${detail.isEmpty ? '' : '\n$detail'}');
    }
    try {
      debugPrint('Gemini raw: ${res.body}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final parts =
          (body['candidates'][0]['content']['parts'] ?? []) as List;
      final text = parts
          .where((p) => p['thought'] != true && p['text'] != null)
          .map((p) => p['text'].toString())
          .join();
      // Ambil hanya bagian {...}, buang teks atau ``` di sekitarnya.
      final st = text.indexOf('{'), en = text.lastIndexOf('}');
      if (st < 0 || en <= st) throw const FormatException('JSON tidak ada');
      final j =
          jsonDecode(text.substring(st, en + 1)) as Map<String, dynamic>;
      double n(String k) => ((j[k] ?? 0) as num).toDouble();
      return Estimate(
        j['is_food'] == true,
        ((j['foods'] ?? []) as List).map((e) => e.toString()).toList(),
        n('carbs_g'),
        n('protein_g'),
        n('fat_g'),
        n('kcal'),
      );
    } catch (_) {
      // DEBUG: tampilkan penyebab asli di layar (hapus setelah masalah beres).
      var why = '';
      try {
        final b = jsonDecode(res.body) as Map<String, dynamic>;
        final c = (b['candidates'] as List?)?.isNotEmpty == true
            ? b['candidates'][0]
            : null;
        why = 'finishReason=${c?['finishReason']}, '
            'blockReason=${b['promptFeedback']?['blockReason']}, '
            'jawaban=${res.body.length > 220 ? res.body.substring(0, 220) : res.body}';
      } catch (_) {
        why = res.body.length > 220 ? res.body.substring(0, 220) : res.body;
      }
      throw Exception('Jawaban AI tidak bisa dibaca.\n[$why]');
    }
  }
}

/// Saat alarm berbunyi, langsung membuka MaagMate (lalu kamera) walau HP sedang
/// terbuka dan app di latar. Native-nya dipasang oleh tool/patch_android.py.
/// Butuh izin "Tampil di atas aplikasi lain"; tanpa itu Android hanya
/// menampilkan notifikasi. Di web / bila native belum ada: tidak berbuat apa-apa.
class AlarmLaunch {
  static const _ch = MethodChannel('maagmate/launch');

  static Future<void> schedule(int id, DateTime when, {bool daily = false}) async {
    if (kIsWeb) return;
    try {
      await _ch.invokeMethod('schedule', {
        'id': id,
        'at': when.millisecondsSinceEpoch,
        'daily': daily,
      });
    } catch (_) {}
  }

  static Future<void> cancel(int id) async {
    if (kIsWeb) return;
    try {
      await _ch.invokeMethod('cancel', {'id': id});
    } catch (_) {}
  }

  static Future<bool> canOverlay() async {
    if (kIsWeb) return true;
    try {
      return (await _ch.invokeMethod<bool>('canOverlay')) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Membuka pengaturan izin bila belum diberikan.
  static Future<void> requestOverlay() async {
    if (kIsWeb) return;
    try {
      await _ch.invokeMethod('requestOverlay');
    } catch (_) {}
  }
}

/// Mengunci layar ke MaagMate selama alarm berbunyi (Android screen pinning).
/// Butuh MainActivity.kt versi baru (lihat MainActivity.kt). Di web atau bila
/// native-nya belum dipasang, semua panggilan diam-diam tidak melakukan apa-apa.
class AlarmLock {
  static const _ch = MethodChannel('maagmate/lock');

  /// Diset true sementara saat berpindah ke app kamera bawaan (itu disengaja).
  static bool leaveAllowed = false;

  static Future<void> start() async {
    if (kIsWeb) return;
    try {
      await _ch.invokeMethod('start');
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }
}