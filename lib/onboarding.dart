import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'screens.dart';
import 'services.dart';

class _Slide {
  final String title, text;
  const _Slide(this.title, this.text);
}

const _slides = [
  _Slide('Alarm yang memastikan kamu makan',
      'Alarm berbunyi sampai kamu memfoto makananmu, jadi jadwal makan tidak terlewat lagi.'),
  _Slide('Foto, lalu AI yang menghitung',
      'Kamera langsung terbuka saat alarm bunyi. AI memperkirakan nama makanan dan kandungan gizinya dari satu foto.'),
  _Slide('Kenali pola keluhanmu',
      'Catat keluhan setelah makan, lihat makanan yang sering menyertainya, lalu bagikan ringkasannya ke dokter.'),
  _Slide('Privasi dan batasan',
      'Catatanmu tersimpan di HP ini. Foto dikirim ke Google Gemini hanya untuk dianalisis. Angka gizi hanya perkiraan dan bukan pengganti dokter.'),
];

/// Animasi berulang sederhana: builder menerima nilai 0..1 yang terus berputar.
class _Loop extends StatefulWidget {
  final Duration duration;
  final Widget Function(double t) builder;
  const _Loop({required this.duration, required this.builder});
  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _c, builder: (_, __) => widget.builder(_c.value));
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _i = 0;
  bool _busy = false;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Store.setOnboarded();
    await Notif.requestPermissions(); // izin notifikasi & alarm, setelah penjelasan
    await AlarmLaunch.requestOverlay(); // izin 'tampil di atas aplikasi lain' agar kamera langsung terbuka
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  void _next() {
    if (_i == _slides.length - 1) {
      _finish();
    } else {
      _page.nextPage(
          duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  // ------------------------------------------------------------ ilustrasi
  Widget _pill(IconData icon, String text, {Color? iconColor}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6))
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: iconColor ?? kGreen),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: kDeep)),
        ]),
      );

  Widget _alarmArt() => SizedBox(
        width: 300,
        height: 280,
        child: _Loop(
          duration: const Duration(milliseconds: 2400),
          builder: (t) {
            double bob(double phase) =>
                math.sin((t + phase) * 2 * math.pi) * 5;
            return Stack(alignment: Alignment.center, children: [
              for (var i = 0; i < 3; i++)
                Builder(builder: (_) {
                  final v = (t + i / 3) % 1.0;
                  return Container(
                    width: 120 + 150 * v,
                    height: 120 + 150 * v,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(.4 * (1 - v)),
                            width: 2)),
                  );
                }),
              Transform.rotate(
                angle: math.sin(t * 2 * math.pi * 5) * .12,
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10))
                    ],
                  ),
                  child: const Icon(Icons.alarm_rounded, color: kGreen, size: 58),
                ),
              ),
              Positioned(
                  left: 0,
                  top: 24 + bob(0),
                  child: _pill(Icons.free_breakfast_rounded, '07.00 Sarapan')),
              Positioned(
                  right: 0,
                  top: 118 + bob(.33),
                  child: _pill(Icons.lunch_dining_rounded, '12.00 Makan siang')),
              Positioned(
                  left: 14,
                  bottom: 18 + bob(.66),
                  child: _pill(Icons.dinner_dining_rounded, '19.00 Makan malam')),
            ]);
          },
        ),
      );

  Widget _corner({required bool top, required bool left}) {
    const side = BorderSide(color: Colors.white, width: 4);
    return Align(
      alignment: Alignment(left ? -1 : 1, top ? -1 : 1),
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(
            top: top ? side : BorderSide.none,
            bottom: top ? BorderSide.none : side,
            left: left ? side : BorderSide.none,
            right: left ? BorderSide.none : side,
          ),
        ),
      ),
    );
  }

  Widget _cameraArt() => SizedBox(
        width: 290,
        height: 300,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 260,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.10),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white24),
              ),
              child: Stack(children: [
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(.16)),
                    child: const Icon(Icons.lunch_dining_rounded,
                        color: Colors.white, size: 64),
                  ),
                ),
                _corner(top: true, left: true),
                _corner(top: true, left: false),
                _corner(top: false, left: true),
                _corner(top: false, left: false),
                _Loop(
                  duration: const Duration(milliseconds: 2200),
                  builder: (t) {
                    final p = t < .5 ? t * 2 : 2 - t * 2;
                    return Align(
                      alignment: Alignment(0, -.78 + 1.56 * p),
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 30),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: LinearGradient(colors: [
                            Colors.white.withOpacity(0),
                            Colors.white,
                            Colors.white.withOpacity(0),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ]),
            ),
          ),
          Positioned(
              left: 28,
              right: 28,
              bottom: 0,
              child: Center(
                  child: _pill(Icons.auto_awesome_rounded, 'Nasi goreng  520 kcal'))),
        ]),
      );

  Widget _chartArt() {
    const vals = [.45, .7, .5, .85, .6, .95, .72];
    const days = ['S', 'S', 'R', 'K', 'J', 'S', 'M'];
    return SizedBox(
      width: 300,
      height: 260,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: const [
                BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10))
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kalori 7 hari terakhir',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: kDeep, fontSize: 13.5)),
              const SizedBox(height: 14),
              SizedBox(
                height: 130,
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: vals[i]),
                                  duration: Duration(milliseconds: 600 + i * 110),
                                  curve: Curves.easeOutCubic,
                                  builder: (_, v, __) => Container(
                                    height: 104 * v,
                                    margin: const EdgeInsets.symmetric(horizontal: 5),
                                    decoration: BoxDecoration(
                                      color: i == 5 ? kGreen : kGreen.withOpacity(.35),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(days[i],
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.black45)),
                              ]),
                        ),
                    ]),
              ),
            ]),
          ),
        ),
        Positioned(
            right: -6,
            bottom: 12,
            child: _pill(Icons.bubble_chart_rounded, 'Kembung 2x minggu ini',
                iconColor: kPink)),
      ]),
    );
  }

  Widget _privacyArt() => SizedBox(
        width: 300,
        height: 280,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            height: 190,
            child: _Loop(
              duration: const Duration(milliseconds: 2600),
              builder: (t) => Stack(alignment: Alignment.center, children: [
                for (var i = 0; i < 2; i++)
                  Builder(builder: (_) {
                    final v = (t + i / 2) % 1.0;
                    return Container(
                      width: 120 + 90 * v,
                      height: 120 + 90 * v,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(.35 * (1 - v)),
                              width: 2)),
                    );
                  }),
                Container(
                  width: 120,
                  height: 120,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10))
                    ],
                  ),
                  child: const Icon(Icons.verified_user_rounded, color: kGreen, size: 64),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            _pill(Icons.smartphone_rounded, 'Data di HP'),
            _pill(Icons.cloud_upload_outlined, 'Foto ke Gemini'),
            _pill(Icons.medical_information_outlined, 'Bukan diagnosis'),
          ]),
        ]),
      );

  Widget _art(int i) {
    final art = [_alarmArt, _cameraArt, _chartArt, _privacyArt][i]();
    return Center(child: FittedBox(fit: BoxFit.scaleDown, child: art));
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final last = _i == _slides.length - 1;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF06231F), kDeep, kGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Stack(children: [
          Positioned(
              top: -90,
              right: -70,
              child: CircleAvatar(
                  radius: 150, backgroundColor: Colors.white.withOpacity(.05))),
          Positioned(
              top: 260,
              left: -110,
              child: CircleAvatar(
                  radius: 120, backgroundColor: Colors.white.withOpacity(.04))),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.16),
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.restaurant_rounded,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text('MaagMate',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 17)),
                      const Spacer(),
                      TextButton(
                        onPressed: last || _busy ? null : _finish,
                        child: Text(last ? '' : 'Lewati',
                            style: const TextStyle(color: Colors.white70)),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _page,
                      itemCount: _slides.length,
                      onPageChanged: (i) => setState(() => _i = i),
                      itemBuilder: (_, i) => _art(i),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 10))
                      ],
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        height: 150,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (c, a) => FadeTransition(
                              opacity: a,
                              child: SlideTransition(
                                  position: Tween<Offset>(
                                          begin: const Offset(0, .12),
                                          end: Offset.zero)
                                      .animate(a),
                                  child: c)),
                          layoutBuilder: (cur, prev) => Stack(
                              alignment: Alignment.topCenter,
                              children: [...prev, if (cur != null) cur]),
                          child: Column(
                            key: ValueKey(_i),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_slides[_i].title,
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: kDeep,
                                      height: 1.25)),
                              const SizedBox(height: 10),
                              Text(_slides[_i].text,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      height: 1.55,
                                      color: Colors.black54)),
                            ],
                          ),
                        ),
                      ),
                      Row(children: [
                        for (var i = 0; i < _slides.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.only(right: 6),
                            width: i == _i ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: i == _i ? kGreen : kGreen.withOpacity(.2),
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        const Spacer(),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: kGreen,
                              minimumSize: const Size(132, 50),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          onPressed: _busy ? null : _next,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(last ? 'Mulai' : 'Lanjut'),
                            const SizedBox(width: 8),
                            Icon(
                                last
                                    ? Icons.check_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 20),
                          ]),
                        ),
                      ]),
                      SizedBox(
                        height: 30,
                        child: Center(
                          child: Text(
                              last
                                  ? 'Setelah ini akan muncul permintaan izin notifikasi dan alarm.'
                                  : '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black45)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}