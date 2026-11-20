import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:device_preview/device_preview.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'onboarding.dart';
import 'screens.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final done = await Store.onboarded();
  // Pemakaian pertama: izin diminta setelah onboarding, bukan langsung saat dibuka.
  try {
    await Notif.init(askPermissions: done);
    for (final r in await Store.reminders()) {
      try {
        await Notif.apply(r);
      } catch (e) {
        debugPrint('Gagal menjadwalkan alarm ${r.id}: $e');
      }
    }
  } catch (e) {
    debugPrint('Gagal init notifikasi: $e');
  }
  runApp(
    // Device Preview hanya aktif di web (untuk demo/presentasi).
    // Di HP asli aplikasi tampil normal tanpa panel.
    DevicePreview(
      enabled: kIsWeb,
      defaultDevice: Devices.ios.iPhone13,
      builder: (context) => MaagMateApp(showOnboarding: !done),
    ),
  );
}

class MaagMateApp extends StatelessWidget {
  final bool showOnboarding;
  const MaagMateApp({super.key, this.showOnboarding = false});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MaagMate',
        debugShowCheckedModeBanner: false,
        locale: DevicePreview.locale(context),
        builder: DevicePreview.appBuilder,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Poppins',
          colorScheme: ColorScheme.fromSeed(seedColor: kGreen),
          scaffoldBackgroundColor: kBg,
          appBarTheme: const AppBarTheme(
            backgroundColor: kBg,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: TextStyle(
                color: kDeep, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE1E9E7))),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          chipTheme: ChipThemeData(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFD5DFDC))),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: Colors.white,
            elevation: 0,
            height: 68,
            surfaceTintColor: Colors.transparent,
            indicatorColor: kGreen.withOpacity(.12),
            iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
                color: s.contains(WidgetState.selected)
                    ? kGreen
                    : Colors.grey.shade600)),
            labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: s.contains(WidgetState.selected)
                    ? kGreen
                    : Colors.grey.shade600)),
          ),
        ),
        home: showOnboarding ? const OnboardingScreen() : const HomeShell(),
      );
}