import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';

import 'about.dart';
import 'models.dart';
import 'services.dart';

/// Buka kamera langsung di dalam aplikasi (bukan pemilih file/dokumen).
Future<XFile?> takePhoto(BuildContext context) =>
    Navigator.of(context).push<XFile>(MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => const CameraScreen()));

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _c;
  List<CameraDescription> _cams = [];
  int _idx = 0;
  String? _err;
  bool _shooting = false;
  bool _opening = false; // true selama kamera sedang dibuka / dibalik

  // Kata-kata penyemangat yang bergantian di atas kamera.
  static const _nudges = [
    'Ayo foto dulu makananmu! 🍽️',
    'Perut sudah lapar, jepret dulu yuk! 📸',
    'Satu foto, satu langkah menuju perut bahagia 😋',
    'Makanannya cantik? Abadikan sebelum disantap! ✨',
    'Lambungmu menunggu kabar baik 💚',
  ];
  int _nudge = 0;
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nudgeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() => _nudge = (_nudge + 1) % _nudges.length);
    });
    _init();
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final c = _c;
    _c = null;
    c?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.paused && _c != null) {
      final c = _c;
      _c = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (st == AppLifecycleState.resumed &&
        _c == null &&
        _err == null &&
        !_opening &&
        _cams.isNotEmpty) {
      _open(_idx);
    }
  }

  Future<void> _init() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        setState(() => _err = 'Kamera tidak ditemukan di perangkat ini.');
        return;
      }
      final back =
          _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      _idx = back < 0 ? 0 : back;
      if (!await _open(_idx) && mounted && _err == null) {
        _fail(_lastError ?? 'Kamera gagal dibuka');
      }
    } catch (e) {
      _fail(e);
    }
  }

  /// Lepas kamera yang sedang aktif. WAJIB selesai dulu sebelum membuka kamera
  /// lain: kebanyakan HP tidak mau membuka kamera depan selama kamera belakang
  /// masih dipakai (hasilnya loading terus).
  Future<void> _release() async {
    final old = _c;
    _c = null;
    if (mounted) setState(() {});
    try {
      await old?.dispose();
    } catch (_) {}
  }

  /// Buka kamera ke-[idx]. Mengembalikan false bila gagal / terlalu lama.
  /// Error TIDAK ditampilkan di sini; pemanggil yang memutuskan.
  Future<bool> _open(int idx) async {
    if (_opening) return false;
    _opening = true;
    try {
      await _release();
      final front = _cams[idx].lensDirection == CameraLensDirection.front;
      final c = CameraController(
          _cams[idx], front ? ResolutionPreset.medium : ResolutionPreset.high,
          enableAudio: false);
      try {
        await c.initialize().timeout(const Duration(seconds: 8));
      } catch (e) {
        try {
          await c.dispose();
        } catch (_) {}
        _lastError = e;
        return false;
      }
      if (!mounted) {
        await c.dispose();
        return false;
      }
      setState(() {
        _c = c;
        _idx = idx;
        _err = null;
      });
      return true;
    } finally {
      _opening = false;
    }
  }

  Object? _lastError;

  void _fail(Object e) {
    if (!mounted) return;
    final code = e is CameraException ? e.code.toLowerCase() : '';
    final detail = e is CameraException
        ? '${e.code}${e.description != null ? ': ${e.description}' : ''}'
        : e.toString();
    setState(() {
      _err = code.contains('denied') || code.contains('permission')
          ? 'Izin kamera ditolak. Izinkan kamera untuk MaagMate di pengaturan${kIsWeb ? ' browser' : ' HP'}, lalu coba lagi.'
          : 'Kamera gagal dibuka.\n\nDetail: $detail';
    });
  }

  Future<void> _shoot() async {
    final c = _c;
    if (c == null || !c.value.isInitialized || _shooting) return;
    setState(() => _shooting = true);
    try {
      final f = await c.takePicture();
      if (mounted) Navigator.of(context).pop(f);
    } catch (_) {
      if (mounted) {
        setState(() => _shooting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Gagal mengambil foto. Coba lagi.')));
      }
    }
  }

  Future<void> _flip() async {
    if (_cams.length < 2 || _opening || _shooting) return;
    final prev = _idx;
    // Pindah depan <-> belakang berdasarkan arah lensa, bukan sekadar urutan
    // daftar (di HP dengan banyak kamera belakang, urutan bisa salah).
    final wanted = _cams[prev].lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    var next = _cams.indexWhere((c) => c.lensDirection == wanted);
    if (next < 0) next = (prev + 1) % _cams.length;
    if (next == prev) return;

    if (await _open(next)) return;
    // Gagal: kembali ke kamera sebelumnya supaya layar tidak macet.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Kamera itu tidak bisa dibuka di perangkat ini.')));
    if (!await _open(prev) && mounted) _fail(_lastError ?? 'Kamera gagal dibuka');
  }

  // Cadangan Android bila CameraX bermasalah: kamera bawaan HP (tetap kamera).
  Future<void> _systemCamera() async {
    AlarmLock.leaveAllowed = true; // pindah ke app kamera bawaan itu sah
    try {
      final f = await ImagePicker().pickImage(
          source: ImageSource.camera, maxWidth: 1024, imageQuality: 80);
      if (f != null && mounted) Navigator.of(context).pop(f);
    } finally {
      AlarmLock.leaveAllowed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: _err != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.no_photography_rounded,
                            color: Colors.white70, size: 56),
                        const SizedBox(height: 14),
                        Text(_err!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 18),
                        FilledButton(
                            onPressed: () {
                              setState(() => _err = null);
                              _cams.isEmpty ? _init() : _open(_idx);
                            },
                            child: const Text('Coba lagi')),
                        if (!kIsWeb)
                          TextButton(
                              onPressed: _systemCamera,
                              child: const Text('Pakai kamera bawaan HP')),
                      ]),
                    ),
                  )
                : (c == null || !c.value.isInitialized)
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white))
                    : Center(child: CameraPreview(c)),
          ),
          // Bingkai kotak pemandu: area di luar kotak digelapkan.
          if (_err == null && c != null && c.value.isInitialized)
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(builder: (context, box) {
                  final size = Size(box.maxWidth, box.maxHeight);
                  final r = _frameRect(size);
                  return Stack(children: [
                    Positioned.fill(
                        child: CustomPaint(painter: _FramePainter())),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: r.bottom + 16,
                      child: const Text(
                        'Taruh makananmu di dalam kotak',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 6)
                          ],
                        ),
                      ),
                    ),
                  ]);
                }),
              ),
            ),
          Positioned(
            left: 8,
            top: 8,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (_err == null)
            Positioned(
              left: 60,
              right: 60,
              top: 12,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.55),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        _nudges[_nudge],
                        key: ValueKey(_nudge),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_cams.length > 1 && _err == null)
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                icon: const Icon(Icons.cameraswitch_rounded,
                    color: Colors.white, size: 30),
                onPressed: _opening ? null : _flip,
              ),
            ),
          if (_err == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: GestureDetector(
                  onTap: _shoot,
                  child: Container(
                    width: 78,
                    height: 78,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4)),
                    child: Container(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _shooting ? Colors.white54 : Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Posisi kotak pemandu di kamera (persegi, sedikit di atas tengah layar).
Rect _frameRect(Size size) {
  final side = math.min(size.width, size.height) * 0.78;
  return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.46),
      width: side,
      height: side);
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const radius = 28.0, len = 38.0;
    final rect = _frameRect(size);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(radius));

    // Gelapkan area di luar kotak (lubang di tengah).
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rr)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = Colors.black.withOpacity(.45));

    // Garis tipis mengelilingi kotak.
    canvas.drawRRect(
        rr,
        Paint()
          ..color = Colors.white.withOpacity(.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Empat sudut tebal.
    final corner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const rad = Radius.circular(radius);
    final l = rect.left, t = rect.top, r = rect.right, b = rect.bottom;
    final path = Path()
      // kiri atas
      ..moveTo(l, t + radius + len)
      ..lineTo(l, t + radius)
      ..arcToPoint(Offset(l + radius, t), radius: rad)
      ..lineTo(l + radius + len, t)
      // kanan atas
      ..moveTo(r - radius - len, t)
      ..lineTo(r - radius, t)
      ..arcToPoint(Offset(r, t + radius), radius: rad)
      ..lineTo(r, t + radius + len)
      // kanan bawah
      ..moveTo(r, b - radius - len)
      ..lineTo(r, b - radius)
      ..arcToPoint(Offset(r - radius, b), radius: rad)
      ..lineTo(r - radius - len, b)
      // kiri bawah
      ..moveTo(l + radius + len, b)
      ..lineTo(l + radius, b)
      ..arcToPoint(Offset(l, b - radius), radius: rad)
      ..lineTo(l, b - radius - len);
    canvas.drawPath(path, corner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

Widget photo(XFile x, {double? height, double? width}) => kIsWeb
    ? Image.network(x.path, height: height, width: width, fit: BoxFit.cover)
    : Image.file(File(x.path), height: height, width: width, fit: BoxFit.cover);

/// Gambar kecil untuk riwayat: data base64 (web) atau file (Android).
Widget? logPhoto(String? p, {double size = 48, double? width}) {
  if (p == null) return null;
  try {
    if (p.startsWith('data:')) {
      return Image.memory(base64Decode(p.substring(p.indexOf(',') + 1)),
          width: width ?? size, height: size, fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (!kIsWeb && File(p).existsSync()) {
      return Image.file(File(p),
          width: width ?? size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round());
    }
  } catch (_) {}
  return null;
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String two(int n) => n.toString().padLeft(2, '0');

Widget fe(String e, {double? l, double? r, double? tp, double? b, double s = 30, double a = 0, double o = .9}) =>
    Positioned(
        left: l,
        right: r,
        top: tp,
        bottom: b,
        child: Transform.rotate(
            angle: a,
            child: Opacity(opacity: o, child: Text(e, style: TextStyle(fontSize: s)))));

/// Kartu bersih: dasar putih, tint tipis, garis halus, bayangan lembut.
Widget pastelCard(
        {required List<Color> g,
        required double radius,
        required Widget child,
        EdgeInsets padding = EdgeInsets.zero}) =>
    Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: g,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE1E9E7)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0F0B3B36), blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Padding(padding: padding, child: child),
    );

class AppBackground extends StatelessWidget {
  const AppBackground({super.key});
  @override
  Widget build(BuildContext context) => const ColoredBox(color: kBg);
}

class PageHeader extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final List<Color> colors; // diabaikan: semua header memakai warna yang sama
  const PageHeader(this.title, this.subtitle, this.icon,
      {this.colors = const [kDeep, kGreen], super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 20, 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [kDeep, kGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Color(0x290B3B36), blurRadius: 16, offset: Offset(0, 6))
          ],
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2)),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Colors.white.withOpacity(.14)),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ]),
      );
}

/// Grafik batang kalori 7 hari terakhir.
class WeekChart extends StatelessWidget {
  final List<MealLog> logs;
  const WeekChart(this.logs, {super.key});

  @override
  Widget build(BuildContext context) {
    const hari = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final now = DateTime.now();
    final days = [for (var i = 6; i >= 0; i--) now.subtract(Duration(days: i))];
    final vals = [
      for (final d in days)
        logs.where((l) => sameDay(l.time, d)).fold<double>(0, (a, b) => a + b.kcal)
    ];
    final mx = vals.fold<double>(500, (a, b) => b > a ? b : a);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Kalori 7 hari terakhir',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(vals[i] > 0 ? '${vals[i].round()}' : '',
                                style: const TextStyle(fontSize: 9)),
                            const SizedBox(height: 2),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              height: 6 + 62 * (vals[i] / mx),
                              decoration: BoxDecoration(
                                color: vals[i] == 0
                                    ? kGreen.withOpacity(.10)
                                    : (i == 6 ? kGreen : kGreen.withOpacity(.4)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(hari[days[i].weekday - 1],
                                style: const TextStyle(fontSize: 11)),
                          ]),
                    ),
                ]),
          ),
        ]),
      ),
    );
  }
}

class StepTile extends StatelessWidget {
  final String n, title, text;
  final IconData icon;
  const StepTile(this.n, this.icon, this.title, this.text, {super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(
                radius: 15,
                backgroundColor: kGreen,
                child: Text(n,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700))),
            const SizedBox(width: 12),
            Icon(icon, color: kGreen, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(text, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ]),
            ),
          ]),
        ),
      );
}

// ===================================================================== Shell
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  int _rev = 0; // naik setelah alarm selesai -> halaman memuat ulang data
  bool _ringing = false;
  Timer? _poll;
  Timer? _webAlarm;
  String? _lastFired;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ringTick.addListener(_check);
    // Web tidak punya notifikasi terjadwal: alarm dicek lewat timer selama tab terbuka.
    if (kIsWeb) {
      _webAlarm = Timer.periodic(const Duration(seconds: 1), (_) => _checkWeb());
    }
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ringTick.removeListener(_check);
    _poll?.cancel();
    _webAlarm?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _checkWeb() async {
    if (_ringing || !mounted) return;
    final n = DateTime.now();
    final key = '${n.year}-${n.month}-${n.day}-${n.hour}-${n.minute}';
    if (_lastFired == key) return;
    for (final r in await Store.reminders()) {
      if (r.on && r.hour == n.hour && r.minute == n.minute) {
        if (_ringing || !mounted) return;
        _lastFired = key;
        _ringing = true;
        await Navigator.of(context).push(MaterialPageRoute(
            fullscreenDialog: true, builder: (_) => RingScreen(id: r.id)));
        _ringing = false;
        if (mounted) setState(() => _rev++);
        return;
      }
    }
  }

  // Bila ada alarm yang sedang berbunyi -> paksa buka layar alarm (kamera).
  Future<void> _check() async {
    if (_ringing || !mounted) return;
    final id = await Notif.activeAlarmId();
    if (id == null || _ringing || !mounted) return;
    _ringing = true;
    await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => RingScreen(id: id)));
    _ringing = false;
    if (mounted) setState(() => _rev++);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(go: (i) => setState(() => _tab = i)),
      const RemindersPage(),
      ScanPage(onSaved: () => setState(() => _tab = 3)),
      const HistoryPage(),
      const FirstAidPage(),
    ];
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: AppBackground()),
        SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: KeyedSubtree(
                        key: ValueKey('$_tab-$_rev'), child: pages[_tab])))),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Beranda'),
          NavigationDestination(icon: Icon(Icons.alarm_rounded), label: 'Alarm'),
          NavigationDestination(
              icon: Icon(Icons.camera_alt_rounded), label: 'Catat'),
          NavigationDestination(
              icon: Icon(Icons.history_rounded), label: 'Riwayat'),
          NavigationDestination(
              icon: Icon(Icons.healing_rounded), label: 'Kambuh?'),
        ],
      ),
    );
  }
}

// ============================================================ Widget bersama
class Macro extends StatelessWidget {
  final String label;
  final double value, max;
  final Color color;
  final String unit;
  const Macro(this.label, this.value, this.max, this.color,
      {this.unit = 'g', super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(
              width: 104,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (value / max).clamp(0.0, 1.0),
                minHeight: 10,
                color: color,
                backgroundColor: color.withOpacity(.15),
              ),
            ),
          ),
          SizedBox(
              width: 64,
              child: Text('±${value.round()} $unit',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}

class NutritionView extends StatelessWidget {
  final Estimate e;
  const NutritionView(this.e, {super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.check_circle, color: kGreen),
            SizedBox(width: 6),
            Text('Makanan terdeteksi',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final f in e.foods)
              Chip(
                label: Text(f),
                backgroundColor: kGreen.withOpacity(.1),
                side: BorderSide.none,
              ),
          ]),
          const SizedBox(height: 8),
          Center(
            child: Text('±${e.kcal.round()} kcal',
                style: const TextStyle(
                    fontSize: 38, fontWeight: FontWeight.w700, color: kGreen)),
          ),
          Macro('Karbo', e.carbs, 130, kYellow),
          Macro('Protein', e.protein, 60, kPink),
          Macro('Lemak', e.fat, 40, kBlue),
          const SizedBox(height: 6),
          const Text(
            'Perkiraan dari foto; porsi, bahan, dan cara masak memengaruhi hasil.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      );
}

MealLog logFrom(Estimate? e, {String foods = '', String? photo}) => MealLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      time: DateTime.now(),
      foods: e == null ? foods : e.foods.join(', '),
      carbs: e?.carbs ?? 0,
      protein: e?.protein ?? 0,
      fat: e?.fat ?? 0,
      kcal: e?.kcal ?? 0,
      complaint: 'Tidak ada',
      photo: photo,
    );

Future<void> addLog(MealLog l) async {
  final logs = await Store.logs();
  logs.insert(0, l);
  await Store.saveLogs(logs);
}

// ================================================================== Beranda
class HomePage extends StatefulWidget {
  final void Function(int) go;
  const HomePage({super.key, required this.go});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Reminder> _rs = [];
  List<MealLog> _logs = [];

  static const tips = [
    'Makan teratur dan jangan menunda waktu makan terlalu lama.',
    'Porsi kecil tapi lebih sering bisa terasa lebih nyaman bagi sebagian orang.',
    'Catat keluhanmu agar kamu mengenali pola pemicu pribadimu.',
    'Hindari langsung berbaring setelah makan.',
  ];

  @override
  void initState() {
    super.initState();
    Store.reminders().then((l) => setState(() => _rs = l));
    Store.logs().then((l) => setState(() => _logs = l));
  }

  String? _topComplaint() {
    final c = <String, int>{};
    for (final l in _logs) {
      if (l.complaint != 'Tidak ada') c[l.complaint] = (c[l.complaint] ?? 0) + 1;
    }
    if (c.isEmpty) return null;
    final k = c.keys.reduce((a, b) => c[a]! >= c[b]! ? a : b);
    return '$k (${c[k]}x)';
  }

  String _greet() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Selamat pagi';
    if (h < 15) return 'Selamat siang';
    if (h < 18) return 'Selamat sore';
    return 'Selamat malam';
  }

  String _nextText() {
    final now = DateTime.now();
    Reminder? best;
    int bestM = 99999;
    for (final r in _rs.where((r) => r.on)) {
      var d = r.hour * 60 + r.minute - (now.hour * 60 + now.minute);
      if (d < 0) d += 1440;
      if (d < bestM) {
        bestM = d;
        best = r;
      }
    }
    if (best == null) return 'Belum ada alarm aktif';
    final t = bestM >= 60 ? '${bestM ~/ 60} j ${bestM % 60} m' : '$bestM menit';
    return '${best.label} ${best.timeText} • $t lagi';
  }

  String? _gapText() {
    final now = DateTime.now();
    if (_logs.isEmpty || now.hour < 7 || now.hour >= 22) return null;
    final today = _logs.where((l) => sameDay(l.time, now)).toList();
    if (today.isEmpty) {
      return now.hour >= 10 ? 'Belum ada makanan tercatat hari ini' : null;
    }
    final last = today.map((l) => l.time).reduce((a, b) => a.isAfter(b) ? a : b);
    final h = now.difference(last).inHours;
    return h >= 5 ? 'Terakhir tercatat makan $h jam lalu' : null;
  }

  Widget _quick(IconData icon, String label, List<Color> g, VoidCallback onTap) =>
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: g),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: g.last.withOpacity(.22),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      );

  Widget _hero() => Container(
        height: 214,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [kDeep, kGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
                color: Color(0x330B3B36), blurRadius: 20, offset: Offset(0, 8))
          ],
        ),
        child: Stack(children: [
          Positioned(
              right: -40,
              top: -40,
              child: CircleAvatar(
                  radius: 100, backgroundColor: Colors.white.withOpacity(.1))),
          Positioned(
            right: 34,
            top: 34,
            child: Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(.12),
                  border: Border.all(color: Colors.white24, width: 1.5)),
              child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 44),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 130),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_greet(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          const Text('Jaga pola makanmu hari ini',
                              style: TextStyle(color: Colors.white70)),
                        ]),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.14),
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.alarm_rounded, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_nextText(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800))),
                    ]),
                  ),
                ]),
          ),
        ]),
      );

  Widget _title(String s) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(s,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: kDeep)),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = _logs.where((l) => sameDay(l.time, now)).toList();
    double sum(double Function(MealLog) f) => today.fold(0, (a, b) => a + f(b));
    final kcal = sum((l) => l.kcal);
    final complaints = today.where((l) => l.complaint != 'Tidak ada').length;
    final tip = tips[now.difference(DateTime(now.year)).inDays % tips.length];

    final gap = _gapText();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      _hero(),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
            child: _quick(Icons.camera_alt_rounded, 'Catat makan',
                const [kGreen, Color(0xFF0B5F58)], () => widget.go(2))),
        const SizedBox(width: 12),
        Expanded(
            child: _quick(Icons.healing_rounded, 'Maag kambuh?',
                const [Color(0xFF1F4F4A), kDeep], () => widget.go(4))),
      ]),
      if (gap != null) ...[
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFFEFF6F4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.schedule_rounded, color: kOrange, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(gap, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Text(
                      'Jeda makan yang terlalu lama bisa memicu keluhan pada sebagian orang.',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            Row(children: [
              SizedBox(
                width: 104,
                height: 104,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: (kcal / 2000).clamp(0.0, 1.0),
                      strokeWidth: 11,
                      strokeCap: StrokeCap.round,
                      color: kGreen,
                      backgroundColor: kGreen.withOpacity(.12),
                    ),
                  ),
                  const Icon(Icons.local_fire_department_rounded, color: kGreen, size: 38),
                ]),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Asupan hari ini',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
                  Text('${kcal.round()} kcal',
                      style: const TextStyle(
                          fontSize: 30, fontWeight: FontWeight.w700, color: kDeep)),
                  const Text('acuan umum 2000 kcal/hari,\nhanya sebagai gambaran',
                      style: TextStyle(fontSize: 11, color: Colors.black45)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Macro('Karbo', sum((l) => l.carbs), 300, kYellow),
            Macro('Protein', sum((l) => l.protein), 80, kPink),
            Macro('Lemak', sum((l) => l.fat), 70, kBlue),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _stat(Icons.restaurant_rounded, '${today.length}', 'makan tercatat', const [kGreen, Color(0xFF0B5F58)])),
        const SizedBox(width: 12),
        Expanded(child: _stat(Icons.sentiment_dissatisfied_rounded, '$complaints', 'keluhan hari ini', const [Color(0xFFC25A45), Color(0xFFA94632)])),
      ]),
      const SizedBox(height: 14),
      WeekChart(_logs),
      const SizedBox(height: 14),
      _title('Jadwal alarm'),
      SizedBox(
        height: 134,
        child: _rs.isEmpty
            ? const Card(child: Center(child: Text('Belum ada alarm.')))
            : ListView(scrollDirection: Axis.horizontal, children: [
                for (final r in _rs)
                  Container(
                    width: 132,
                    margin: const EdgeInsets.only(right: 12, bottom: 8),
                    child: pastelCard(
                      g: r.on
                          ? mealGradient(r.label)
                          : const [Color(0xFFE8EEEC), Color(0xFFD5DDDA)],
                      radius: 22,
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(mealIcon(r.label), color: kDeep, size: 30),
                        const Spacer(),
                        Text(r.timeText,
                            style: const TextStyle(
                                color: kDeep, fontSize: 22, fontWeight: FontWeight.w700)),
                        Text(r.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      ]),
                    ),
                  ),
              ]),
      ),
      if (_topComplaint() != null) ...[
        const SizedBox(height: 6),
        Card(
          color: const Color(0xFFFBEFED),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.push_pin_rounded, color: kPink, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Keluhan tersering: ${_topComplaint()}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Text('Lihat di Riwayat makanan apa yang menyertainya.',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Card(
        color: const Color(0xFFEFF6F4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.lightbulb_rounded, color: kOrange, size: 30),
            const SizedBox(width: 12),
            Expanded(child: Text(tip, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.shield_outlined, color: kGreen),
          title: const Text('Tentang & privasi',
              style: TextStyle(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AboutPage())),
        ),
      ),
    ]);
  }

  Widget _stat(IconData icon, String v, String l, List<Color> g) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: g.last.withOpacity(.22), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.white.withOpacity(.18)),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              Text(l, style: const TextStyle(color: Colors.white, fontSize: 11)),
            ]),
          ),
        ]),
      );
}

// ================================================================== Alarm
class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});
  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  List<Reminder> _items = [];
  String _soundName = '';

  @override
  void initState() {
    super.initState();
    Store.reminders().then((l) => setState(() => _items = l));
    _loadSound();
  }

  Future<void> _loadSound() async {
    final s = await Sounds.selected();
    if (mounted) setState(() => _soundName = s.name);
  }

  Future<void> _chooseSound() async {
    final cur = await Sounds.selected();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => SoundSheet(selectedId: cur.id),
    );
    _loadSound();
  }

  void _sort() => _items.sort(
      (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

  Future<void> _persist() => Store.saveReminders(_items);

  Future<void> _add() async {
    final t = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 12, minute: 0));
    if (t == null || !mounted) return;
    final c = TextEditingController(text: 'Makan');
    final label = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nama alarm'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text), child: const Text('Simpan')),
        ],
      ),
    );
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000 % 1000000;
    final r = Reminder(
        id: id,
        hour: t.hour,
        minute: t.minute,
        label: (label == null || label.trim().isEmpty) ? 'Makan' : label.trim());
    setState(() {
      _items = [..._items, r];
      _sort();
    });
    await Notif.apply(r);
    await _persist();
  }

  Future<void> _retime(Reminder r) async {
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: r.hour, minute: r.minute));
    if (t == null) return;
    final n = r.copyWith(hour: t.hour, minute: t.minute);
    setState(() {
      _items = _items.map((e) => e.id == r.id ? n : e).toList();
      _sort();
    });
    await Notif.apply(n);
    await _persist();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: kGreen,
          foregroundColor: Colors.white,
          onPressed: _add,
          icon: const Icon(Icons.add_alarm_rounded),
          label: const Text('Tambah'),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
          const PageHeader('Alarm Makan',
              'Berhenti hanya setelah foto makanan', Icons.alarm_rounded,
              colors: [Color(0xFF5B54D6), Color(0xFF9B8CFF)]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: const Color(0xFFEFF6F4),
                borderRadius: BorderRadius.circular(18)),
            child: const Row(children: [
              Icon(Icons.camera_alt_rounded, color: kOrange, size: 26),
              SizedBox(width: 10),
              Expanded(
                  child: Text(
                      'Saat alarm bunyi, kamera terbuka otomatis. Alarm baru berhenti setelah kamu memfoto makananmu.')),
            ]),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.music_note_rounded, color: kPurple),
              title: const Text('Lagu alarm',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(_soundName.isEmpty ? '...' : _soundName),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _chooseSound,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: const ExpansionTile(
                leading: Icon(Icons.settings_suggest_rounded, color: kGreen),
                title: Text('Alarm tidak bunyi? Cek pengaturan HP',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• Android 12+: izinkan "Alarm & pengingat" di pengaturan aplikasi MaagMate.\n'
                      '• Bila layar tidak menyala saat alarm: izinkan notifikasi layar penuh / tampil di layar kunci.\n'
                      '• Xiaomi, Oppo, Vivo, Realme: aktifkan "Autostart" dan matikan penghemat baterai untuk MaagMate.\n'
                      '• Coba tombol "Coba alarm" di bawah dengan layar terkunci untuk memastikan semuanya berfungsi.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final r in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Dismissible(
                key: ValueKey(r.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  decoration: BoxDecoration(
                      color: Colors.red.shade300,
                      borderRadius: BorderRadius.circular(26)),
                  child: const Icon(Icons.delete_rounded, color: Colors.white),
                ),
                onDismissed: (_) async {
                  setState(() => _items.removeWhere((e) => e.id == r.id));
                  await Notif.cancel(r.id);
                  await _persist();
                },
                child: pastelCard(
                  g: r.on
                      ? mealGradient(r.label)
                      : const [Color(0xFFE8EEEC), Color(0xFFD5DDDA)],
                  radius: 26,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(26),
                      onTap: () => _retime(r),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(children: [
                          Container(
                            width: 60,
                            height: 60,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(.65),
                                shape: BoxShape.circle),
                            child: Icon(mealIcon(r.label), color: kDeep, size: 30),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.label,
                                      style: const TextStyle(
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w700)),
                                  Text(r.timeText,
                                      style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.w700,
                                          color: kDeep)),
                                ]),
                          ),
                          Switch(
                            value: r.on,
                            activeColor: Colors.white,
                            activeTrackColor: kGreen,
                            onChanged: (v) async {
                              final n = r.copyWith(on: v);
                              setState(() => _items =
                                  _items.map((e) => e.id == r.id ? n : e).toList());
                              await Notif.apply(n);
                              await _persist();
                            },
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              if (kIsWeb) {
                // Simulasi di web: langsung buka layar alarm.
                Navigator.of(context).push(MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const RingScreen(id: 999)));
                return;
              }
              if (!await AlarmLaunch.canOverlay()) {
                if (!mounted) return;
                final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                          title: const Text('Izin kamera otomatis'),
                          content: const Text(
                              'Agar kamera langsung terbuka saat alarm berbunyi (walau HP sedang dipakai), aktifkan "Tampil di atas aplikasi lain" untuk MaagMate.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Nanti')),
                            FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Buka pengaturan')),
                          ],
                        ));
                if (ok == true) {
                  await AlarmLaunch.requestOverlay();
                  return;
                }
              }
              final err = await Notif.test();
              if (!mounted) return;
              if (err != null) {
                showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                          title: const Text('Alarm gagal'),
                          content: SelectableText(err),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('OK'))
                          ],
                        ));
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Alarm uji coba bunyi 5 detik lagi. Kunci layar untuk mencoba.')));
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(kIsWeb ? 'Simulasi alarm' : 'Coba alarm (5 detik)'),
          ),
        ]),
      );
}

// ============================================================ Pilih lagu
class SoundSheet extends StatefulWidget {
  final String selectedId;
  const SoundSheet({super.key, required this.selectedId});
  @override
  State<SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<SoundSheet> {
  final _player = AudioPlayer();
  List<SoundItem> _all = [];
  late String _sel = widget.selectedId;
  String? _playing;

  @override
  void initState() {
    super.initState();
    _load();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await Sounds.all();
    if (mounted) setState(() => _all = l);
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _toggle(SoundItem s) async {
    if (_playing == s.id) {
      await _player.stop();
      setState(() => _playing = null);
      return;
    }
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(Sounds.source(s));
      setState(() => _playing = s.id);
    } catch (_) {
      _snack('Lagu ini tidak bisa diputar.');
    }
  }

  Future<void> _choose(SoundItem s) async {
    await Sounds.select(s.id);
    setState(() => _sel = s.id);
  }

  Future<void> _add() async {
    try {
      final it = await Sounds.addCustom();
      if (it == null) return;
      await _load();
      await _choose(it);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _remove(SoundItem s) async {
    if (_playing == s.id) {
      await _player.stop();
      _playing = null;
    }
    await Sounds.removeCustom(s.id);
    if (_sel == s.id) _sel = Sounds.defaultId;
    await _load();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Pilih lagu alarm',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kDeep)),
          const SizedBox(height: 6),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final s in _all)
                ListTile(
                  leading: Icon(
                      _sel == s.id
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: _sel == s.id ? kGreen : Colors.grey),
                  title: Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: s.custom ? const Text('Lagu kamu') : null,
                  onTap: () => _choose(s),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Dengarkan',
                      icon: Icon(
                          _playing == s.id
                              ? Icons.stop_circle_rounded
                              : Icons.play_circle_rounded,
                          color: kOrange,
                          size: 30),
                      onPressed: () => _toggle(s),
                    ),
                    if (s.custom)
                      IconButton(
                        tooltip: 'Hapus',
                        icon: Icon(Icons.delete_outline_rounded,
                            color: Colors.red.shade300),
                        onPressed: () => _remove(s),
                      ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _add,
              icon: const Icon(Icons.library_music_rounded),
              label: const Text('Tambah lagu dari HP'),
            ),
          ),
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Di versi web, lagu tambahan hilang kalau halaman di-refresh.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ),
        ]),
      );
}

// ================================================================ Layar alarm
class RingScreen extends StatefulWidget {
  final int id;
  const RingScreen({super.key, required this.id});
  @override
  State<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends State<RingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  final _player = AudioPlayer();
  Timer? _clock;
  String _label = 'Makan';
  bool _busy = false, _done = false;
  int _fails = 0;
  String? _msg;
  Estimate? _est;
  XFile? _img;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AlarmLock.start(); // Android: kunci layar ke MaagMate sampai foto diambil
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    _startSound();
    // Kamera langsung terbuka begitu alarm berbunyi.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _snap(auto: true);
    });
    Store.reminders().then((l) {
      for (final r in l) {
        if (r.id == widget.id) setState(() => _label = r.label);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AlarmLock.stop();
    _player.dispose();
    _pulse.dispose();
    _clock?.cancel();
    super.dispose();
  }

  // Kalau pengguna berhasil keluar dari layar alarm (home / app lain) sebelum
  // foto: bunyikan alarm keras lewat notifikasi supaya tetap mengganggu, dan
  // ketukannya membawa kembali ke sini. Saat kembali, mode senyap dipulihkan.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (_done || kIsWeb) return;
    if (s == AppLifecycleState.paused && !AlarmLock.leaveAllowed) {
      _player.pause();
      Notif.loud(widget.id, _label);
    } else if (s == AppLifecycleState.resumed) {
      _player.resume();
      Notif.quiet(widget.id);
    }
  }

  bool _quieted = false;

  Future<void> _startSound() async {
    try {
      if (!_quieted) {
        _quieted = true;
        await Notif.quiet(widget.id); // hentikan bunyi bawaan notifikasi
      }
      await _player.setReleaseMode(ReleaseMode.loop);
      final s = await Sounds.selected();
      try {
        await _player.play(Sounds.source(s), volume: 1.0);
      } catch (_) {
        // Lagu pilihan gagal diputar -> pakai alarm bawaan.
        await _player.play(AssetSource('alarm.wav'), volume: 1.0);
      }
    } catch (e) {
      debugPrint('Suara gagal: $e');
      if (mounted) setState(() => _msg = 'Suara gagal diputar: $e');
    }
  }

  Future<void> _snap({bool auto = false}) async {
    final f = await takePhoto(context);
    if (!mounted) return;
    if (f == null) {
      if (!auto) setState(() => _msg = 'Foto dibatalkan. Alarm tetap bunyi.');
      return;
    }
    setState(() {
      _img = f;
      _busy = true;
      _msg = null;
    });
    try {
      final e = await Nutrition.estimate(f);
      if (!e.isFood) {
        setState(() => _msg = 'Itu sepertinya bukan makanan. Foto makananmu ya.');
        return;
      }
      await _finish(e);
    } catch (e) {
      _fails++;
      setState(() => _msg = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Alarm hanya berhenti di sini, setelah ada foto.
  Future<void> _finish(Estimate? e) async {
    await _player.stop();
    await AlarmLock.stop();
    await Notif.stop(widget.id);
    final p = _img == null ? null : await Store.savePhoto(_img!);
    await addLog(logFrom(e, foods: 'Makan (tanpa analisis AI)', photo: p));
    if (mounted) setState(() {
      _est = e;
      _done = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    return PopScope(
      canPop: _done,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF06231F), kDeep, Color(0xFF0F766E)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: _done ? _doneView() : _ringView(n),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _ringView(DateTime n) => [
        const SizedBox(height: 24),
        SizedBox(
          height: 210,
          child: Stack(alignment: Alignment.center, children: [
            for (var i = 0; i < 3; i++)
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  final v = (_pulse.value + i / 3) % 1.0;
                  return Container(
                    width: 120 + 90 * v,
                    height: 120 + 90 * v,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(.5 * (1 - v)),
                            width: 3)),
                  );
                },
              ),
            Container(
              width: 120,
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(.22),
                  boxShadow: [
                    BoxShadow(color: Colors.white.withOpacity(.18), blurRadius: 40)
                  ]),
              child: Icon(mealIcon(_label), color: Colors.white, size: 60),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text('${two(n.hour)}.${two(n.minute)}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 64, fontWeight: FontWeight.w700)),
        ),
        Center(
          child: Text('Waktunya $_label!',
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text('Foto makananmu untuk mematikan alarm',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 15)),
        ),
        const SizedBox(height: 28),
        if (_img != null && _busy)
          ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: photo(_img!, height: 180)),
        if (_busy)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(color: Colors.white))),
        if (_msg != null)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Text(_msg!, style: const TextStyle(color: Colors.red)),
          ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kDeep,
              minimumSize: const Size.fromHeight(60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: _busy ? null : _snap,
          icon: const Icon(Icons.camera_alt_rounded, size: 28),
          label: const Text('Foto makanan', style: TextStyle(fontSize: 18)),
        ),
        TextButton.icon(
          onPressed: _startSound,
          icon: const Icon(Icons.volume_up_rounded, color: Colors.white70, size: 18),
          label: const Text('Suara tidak bunyi? Ketuk di sini',
              style: TextStyle(color: Colors.white70)),
        ),
        if (_fails >= 2 && _img != null && !_busy)
          TextButton(
            onPressed: () => _finish(null),
            child: const Text('AI bermasalah? Pakai foto ini tanpa analisis',
                style: TextStyle(color: Colors.white)),
          ),
      ];

  List<Widget> _doneView() => [
        const SizedBox(height: 16),
        const Center(child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 76)),
        const Center(
          child: Text('Alarm dimatikan. Selamat makan!',
              style: TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 16),
        if (_est != null)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18), child: NutritionView(_est!))),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kDeep,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Selesai'),
        ),
      ];
}

// ================================================================== Catat
class ScanPage extends StatefulWidget {
  final VoidCallback onSaved;
  const ScanPage({super.key, required this.onSaved});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  XFile? _image;
  Estimate? _est;
  bool _busy = false;
  String? _error;
  String _complaint = 'Tidak ada';
  List<MealLog> _logs = [];
  double _portion = 1;
  List<String>? _names;

  static const _portions = {
    'Setengah': 0.5,
    'Normal': 1.0,
    'Banyak': 1.5,
    'Dobel': 2.0,
  };

  // Hasil AI setelah porsi/nama dikoreksi pengguna.
  Estimate? get _shown => _est?.scaled(_portion, foods: _names);

  @override
  void initState() {
    super.initState();
    Store.logs().then((l) => setState(() => _logs = l));
  }

  Future<void> _rename() async {
    final c = TextEditingController(text: _shown?.foods.join(', ') ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nama makanan'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(helperText: 'Pisahkan dengan koma')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Simpan')),
        ],
      ),
    );
    if (v == null) return;
    final n = v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (n.isNotEmpty) setState(() => _names = n);
  }

  Future<void> _pick() async {
    final f = await takePhoto(context);
    if (f == null || !mounted) return;
    setState(() {
      _image = f;
      _est = null;
      _portion = 1;
      _names = null;
      _error = null;
      _busy = true;
    });
    try {
      final e = await Nutrition.estimate(f);
      setState(() => _est = e);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final p = _image == null ? null : await Store.savePhoto(_image!);
    final l = logFrom(_shown, photo: p);
    l.complaint = _complaint;
    await addLog(l);
    setState(() {
      _image = null;
      _est = null;
      _portion = 1;
      _names = null;
      _complaint = 'Tidak ada';
    });
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final e = _shown;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const PageHeader('Catat Makanan', 'Foto langsung dari kamera', Icons.camera_alt_rounded,
          colors: [kOrange, kPink]),
      const SizedBox(height: 14),
      InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _busy ? null : _pick,
        child: Container(
          height: 230,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
                colors: [kGreen, kDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            boxShadow: [
              BoxShadow(color: Color(0x290B3B36), blurRadius: 16, offset: Offset(0, 6))
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _image != null
              ? photo(_image!, width: double.infinity)
              : Stack(children: [
                  Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: const [
                              BoxShadow(color: Color(0x33000000), blurRadius: 16)
                            ]),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: kGreen, size: 40),
                      ),
                      const SizedBox(height: 12),
                      const Text('Ketuk untuk foto makanan',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ]),
        ),
      ),
      if (_image == null && _est == null && !_busy) ...[
        const SizedBox(height: 18),
        const Text('Cara kerja',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: kDeep)),
        const SizedBox(height: 8),
        const StepTile('1', Icons.camera_alt_rounded, 'Foto makananmu', 'Langsung dari kamera, bukan album.'),
        const SizedBox(height: 8),
        const StepTile('2', Icons.auto_awesome_rounded, 'AI mengenali & memperkirakan gizi', 'Karbo, protein, lemak, dan kalori.'),
        const SizedBox(height: 8),
        const StepTile('3', Icons.edit_note_rounded, 'Catat keluhan', 'Agar kamu mengenali pola pemicu pribadimu.'),
        const SizedBox(height: 18),
        WeekChart(_logs),
        const SizedBox(height: 14),
        Text('Makan hari ini',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: kDeep)),
        const SizedBox(height: 8),
        if (_logs.where((l) => sameDay(l.time, DateTime.now())).isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Belum ada makanan tercatat hari ini.')))
        else
          for (final l in _logs.where((l) => sameDay(l.time, DateTime.now())))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: Icon(complaintIcon(l.complaint), color: kGreen, size: 28),
                  title: Text(l.foods.isEmpty ? 'Makanan' : l.foods,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${two(l.time.hour)}.${two(l.time.minute)} • ${l.kcal.round()} kcal'),
                ),
              ),
            ),
      ],
      if (_busy)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: kGreen))),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.red))),
      if (e != null && !e.isFood)
        const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('Ini sepertinya bukan makanan. Coba foto lagi.')),
      if (e != null && e.isFood) ...[
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: NutritionView(e))),
        const SizedBox(height: 12),
        const Text('Porsi tidak pas? Sesuaikan agar angkanya lebih akurat',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final p in _portions.entries)
            ChoiceChip(
              label: Text(p.key),
              selected: _portion == p.value,
              selectedColor: kGreen.withOpacity(.18),
              onSelected: (_) => setState(() => _portion = p.value),
            ),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _rename,
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Ubah nama makanan'),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Keluhan setelah makan (isi bila sudah terasa)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final c in complaintEmoji.keys)
            ChoiceChip(
              avatar: Icon(complaintIcon(c), size: 18),
              label: Text(c),
              selected: _complaint == c,
              selectedColor: kGreen.withOpacity(.18),
              onSelected: (_) => setState(() => _complaint = c),
            ),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Makanan/minuman tertentu dapat memicu keluhan pada sebagian orang. Catat agar kamu bisa mengenali pola pribadimu.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: kGreen, minimumSize: const Size.fromHeight(54)),
            onPressed: _save,
            child: const Text('Simpan ke riwayat')),
      ],
    ]);
  }
}

// ================================================================= Riwayat
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<MealLog> _logs = [];

  @override
  void initState() {
    super.initState();
    Store.logs().then((l) => setState(() => _logs = l));
  }

  String _day(DateTime t) {
    final n = DateTime.now();
    if (sameDay(t, n)) return 'Hari ini';
    if (sameDay(t, n.subtract(const Duration(days: 1)))) return 'Kemarin';
    return '${t.day}/${t.month}/${t.year}';
  }

  Future<void> _copySummary() async {
    await Clipboard.setData(ClipboardData(text: doctorSummary(_logs)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ringkasan disalin. Tempel di WhatsApp atau catatan untuk ditunjukkan ke dokter.')));
  }

  Future<void> _rename(MealLog l) async {
    final c = TextEditingController(text: l.foods);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nama makanan'),
        content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(helperText: 'Pisahkan dengan koma')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Simpan')),
        ],
      ),
    );
    if (v == null || v.trim().isEmpty) return;
    setState(() => l.foods = v.trim());
    await Store.saveLogs(_logs);
  }

  List<Widget> _insight() {
    final t = findTriggers(_logs);
    return [
      if (t.isNotEmpty)
        Card(
          color: const Color(0xFFFBEFED),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.search_rounded, color: kPink),
                SizedBox(width: 8),
                Expanded(
                    child: Text('Makanan yang sering menyertai keluhan',
                        style: TextStyle(fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 8),
              for (final x in t)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                      '• ${cap(x.name)} — keluhan ${x.bad} dari ${x.total} kali makan',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 4),
              const Text(
                  'Ini hanya pola dari catatanmu, bukan diagnosis. Banyak faktor lain berpengaruh; bicarakan dengan dokter bila keluhan sering muncul.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        ),
      const SizedBox(height: 10),
      Card(
        color: const Color(0xFFEAF6F2),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.restaurant_menu_rounded, color: kGreen),
              SizedBox(width: 8),
              Expanded(
                  child: Text('Saran menu',
                      style: TextStyle(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            for (final x in swapSuggestions(t))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $x',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (swapSuggestions(t).isNotEmpty) const SizedBox(height: 6),
            const Text('Pilihan yang umumnya lebih ramah lambung:',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            for (final x in gentleMenu)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $x'),
              ),
            const SizedBox(height: 6),
            const Text(
                'Saran umum, bukan diagnosis atau pengganti dokter/ahli gizi. Tiap orang bereaksi berbeda; makan porsi kecil tapi teratur biasanya lebih nyaman.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _copySummary,
        icon: const Icon(Icons.copy_rounded),
        label: const Text('Salin ringkasan 14 hari (untuk dokter)'),
      ),
    ];
  }

  Future<void> _edit(MealLog l) async {
    final big = logPhoto(l.photo, size: 220, width: double.infinity);
    final c = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (big != null) ...[
            ClipRRect(borderRadius: BorderRadius.circular(16), child: big),
            const SizedBox(height: 12),
          ],
          Text(l.foods.isEmpty ? 'Makanan' : l.foods,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('Keluhan setelah makan ini?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in complaintEmoji.keys)
              ActionChip(
                  avatar: Icon(complaintIcon(k), size: 18),
                  label: Text(k),
                  onPressed: () => Navigator.pop(context, k)),
          ]),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Navigator.pop(context, '__rename'),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: const Text('Ubah nama makanan'),
          ),
        ]),
      ),
    );
    if (c == null) return;
    if (c == '__rename') {
      await _rename(l);
      return;
    }
    setState(() => l.complaint = c);
    await Store.saveLogs(_logs);
  }

  @override
  Widget build(BuildContext context) {
    if (_logs.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const PageHeader('Riwayat', 'Pola makan & keluhanmu', Icons.menu_book_rounded,
            colors: [Color(0xFF2563EB), Color(0xFF54A0FF)]),
        const SizedBox(height: 14),
        WeekChart(_logs),
        const SizedBox(height: 14),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(children: [
              Icon(Icons.restaurant_menu_rounded, size: 56, color: kGreen),
              SizedBox(height: 8),
              Text('Belum ada catatan makan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Foto makananmu saat alarm bunyi, nanti muncul di sini.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54)),
            ]),
          ),
        ),
      ]);
    }
    final withC = _logs.where((l) => l.complaint != 'Tidak ada').length;
    final items = <Widget>[
      PageHeader('Riwayat',
          '$withC keluhan dari ${_logs.length} kali makan', Icons.menu_book_rounded,
          colors: const [Color(0xFF2563EB), Color(0xFF54A0FF)]),
      const SizedBox(height: 14),
      WeekChart(_logs),
      const SizedBox(height: 14),
      ..._insight(),
      const SizedBox(height: 8),
      const Text('Ketuk catatan untuk mengubah keluhan atau nama makanan, geser untuk menghapus.',
          style: TextStyle(fontSize: 11, color: Colors.black45)),
    ];
    String? last;
    for (final l in _logs) {
      final d = _day(l.time);
      if (d != last) {
        last = d;
        final kc = _logs
            .where((x) => sameDay(x.time, l.time))
            .fold<double>(0, (a, b) => a + b.kcal);
        items.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(children: [
            Text(d, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            Text('${kc.round()} kcal',
                style: const TextStyle(color: kOrange, fontWeight: FontWeight.w800)),
          ]),
        ));
      }
      final bad = l.complaint != 'Tidak ada';
      final pic = logPhoto(l.photo);
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Dismissible(
          key: ValueKey(l.id),
          direction: DismissDirection.endToStart,
          background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              decoration: BoxDecoration(
                  color: Colors.red.shade300,
                  borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.delete_rounded, color: Colors.white)),
          onDismissed: (_) async {
            Store.deletePhoto(l.photo);
            setState(() => _logs.removeWhere((x) => x.id == l.id));
            await Store.saveLogs(_logs);
          },
          child: Card(
            child: ListTile(
              onTap: () => _edit(l),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              leading: pic != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12), child: pic)
                  : CircleAvatar(
                      backgroundColor: (bad ? kOrange : kGreen).withOpacity(.15),
                      child: Icon(complaintIcon(l.complaint),
                          color: bad ? kOrange : kGreen, size: 22)),
              title: Text(l.foods.isEmpty ? 'Makanan' : l.foods,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  '${two(l.time.hour)}.${two(l.time.minute)} • K ${l.carbs.round()}g • P ${l.protein.round()}g • L ${l.fat.round()}g • ${l.kcal.round()} kcal'),
              trailing: bad
                  ? Chip(
                      label: Text(l.complaint),
                      backgroundColor: kOrange.withOpacity(.15),
                      side: BorderSide.none)
                  : null,
            ),
          ),
        ),
      ));
    }
    return ListView(padding: const EdgeInsets.all(16), children: items);
  }
}

// ============================================================= Maag Kambuh
class FirstAidPage extends StatelessWidget {
  const FirstAidPage({super.key});

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.event_seat_rounded, 'Duduk tegak dan hindari langsung berbaring.'),
      (Icons.checkroom_rounded, 'Longgarkan pakaian yang menekan perut.'),
      (Icons.water_drop_rounded, 'Minum air secukupnya jika terasa nyaman.'),
      (Icons.no_food_rounded, 'Hindari sementara makanan/minuman yang biasanya memicu keluhanmu, misalnya yang sangat pedas atau berkafein.'),
      (Icons.edit_note_rounded, 'Catat keluhanmu di tab Catat atau Riwayat.'),
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      const PageHeader('Maag Kambuh?', 'Tindakan awal saat keluhan muncul', Icons.medical_services_rounded,
          colors: [Color(0xFFEE5A6F), Color(0xFFFF9A8B)]),
      const SizedBox(height: 14),
      for (final s in steps)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            color: kTints[steps.indexOf(s) % kTints.length],
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(s.$1, color: kDeep, size: 28),
                const SizedBox(width: 14),
                Expanded(child: Text(s.$2)),
              ]),
            ),
          ),
        ),
      const Text('Panduan ini bukan pengobatan dan tidak menggantikan dokter.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 14),
      const Card(
        color: Color(0xFFEFF6F4),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.shield_rounded, color: kGreen),
              SizedBox(width: 8),
              Text('Pencegahan sehari-hari',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            SizedBox(height: 8),
            Text('• Makan teratur; jangan menunda atau melewatkan waktu makan.\n'
                '• Porsi lebih kecil tapi lebih sering bisa terasa lebih nyaman.\n'
                '• Kurangi makanan/minuman yang kamu tahu memicu keluhan (misalnya pedas, asam, berlemak, kafein, bersoda).\n'
                '• Beri jeda beberapa jam antara makan terakhir dan berbaring/tidur.\n'
                '• Hindari rokok dan alkohol; kelola stres dan tidur cukup.\n'
                '• Obat pereda nyeri tertentu (misalnya ibuprofen, aspirin) dapat mengiritasi lambung; tanyakan dokter atau apoteker sebelum memakainya.'),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      const Card(
        color: Color(0xFFEFF6F4),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.local_hospital_rounded, color: kOrange),
              SizedBox(width: 8),
              Expanded(
                  child: Text('Sebaiknya periksa ke dokter bila:',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            ]),
            SizedBox(height: 8),
            Text('• Keluhan sering berulang atau berlangsung lebih dari 2 minggu\n'
                '• Berat badan turun tanpa sebab yang jelas\n'
                '• Sulit atau nyeri saat menelan\n'
                '• Muntah terus-menerus\n\n'
                'Tab Riwayat punya tombol "Salin ringkasan" yang bisa kamu tunjukkan ke dokter.'),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.red.shade50,
            border: Border.all(color: Colors.red.shade200),
            borderRadius: BorderRadius.circular(22)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(
              child: Text('Segera cari pertolongan medis jika:',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ]),
          SizedBox(height: 8),
          Text('• Nyeri dada berat\n• Muntah darah\n• BAB hitam\n• Pingsan\n• Nyeri hebat yang tidak membaik'),
          SizedBox(height: 10),
          Text('Darurat di Indonesia: telepon 112 atau 119.',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }
}