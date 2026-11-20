import 'package:flutter/material.dart';

import 'models.dart';
import 'services.dart';

const kAppVersion = '1.0.0';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Widget _section(IconData icon, String title, String text) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: kGreen, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: kDeep, fontSize: 15)),
                const SizedBox(height: 4),
                Text(text,
                    style: const TextStyle(
                        fontSize: 13, height: 1.45, color: Colors.black54)),
              ]),
            ),
          ]),
        ),
      );

  Future<void> _clear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus semua catatan makan?'),
        content: const Text(
            'Seluruh riwayat makan, foto, dan keluhanmu di HP ini akan dihapus dan tidak bisa dikembalikan. Jadwal alarm tidak ikut dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    await Store.clearLogs();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Semua catatan makan dihapus.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        appBar: AppBar(title: const Text('Tentang & Privasi')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
              _section(Icons.restaurant_rounded, 'MaagMate $kAppVersion',
                  'Pengingat makan dan pencatat pola makan untuk membantu menjaga lambung. Alarm baru berhenti setelah kamu memfoto makananmu.'),
              const SizedBox(height: 10),
              _section(Icons.lock_outline_rounded, 'Data tersimpan di HP-mu',
                  'Riwayat makan, foto makanan, keluhan, jadwal alarm, dan lagu pilihanmu disimpan di perangkat ini. MaagMate tidak punya akun dan tidak mengunggah catatanmu ke server milik kami. Bila aplikasi dihapus, datanya ikut hilang.'),
              const SizedBox(height: 10),
              _section(Icons.cloud_upload_outlined, 'Foto dikirim ke Google Gemini',
                  'Saat kamu memfoto makanan, foto itu dikirim ke layanan Google Gemini untuk memperkirakan nama makanan dan kandungan gizinya. Salinan foto disimpan di HP-mu agar muncul di Riwayat, dan terhapus saat catatannya dihapus. Hindari memfoto hal yang bersifat pribadi.'),
              const SizedBox(height: 10),
              _section(Icons.verified_user_outlined, 'Izin yang dipakai',
                  'Kamera: memfoto makanan. Notifikasi dan alarm: membunyikan pengingat tepat waktu. Layar penuh: membuka layar alarm saat HP terkunci. Penyimpanan/berkas: hanya saat kamu menambahkan lagu alarm sendiri.'),
              const SizedBox(height: 10),
              _section(Icons.medical_information_outlined, 'Bukan alat medis',
                  'Angka gizi hanyalah perkiraan dari foto. Pola keluhan berasal dari catatanmu sendiri dan bukan diagnosis. MaagMate tidak menggantikan dokter. Bila nyeri hebat, muntah darah, atau BAB hitam, segera ke fasilitas kesehatan.'),
              const SizedBox(height: 10),
              _section(Icons.library_music_outlined, 'Lagu dan font',
                  'Lagu bawaan adalah komposisi domain publik (Beethoven, Twinkle Twinkle) yang disintesis sendiri. Font Poppins berlisensi SIL Open Font License 1.1.'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: Colors.red.shade600),
                onPressed: () => _clear(context),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Hapus semua catatan makan'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'MaagMate',
                    applicationVersion: kAppVersion),
                child: const Text('Lisensi open source'),
              ),
            ]),
          ),
        ),
      );
}