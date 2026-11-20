# MaagMate

Alarm makan bunyi → kamera (langsung di dalam app) terbuka otomatis → alarm baru berhenti setelah foto makanan → AI mengenali makanan + estimasi gizi → riwayat makan & keluhan. Plus halaman "Maag Kambuh?".

## Cara build APK
1. Pastikan `flutter doctor` hijau (Flutter + Android SDK).
2. Di folder ini: `./setup.sh`
3. Ambil API key gratis di https://aistudio.google.com/apikey
4. `flutter build apk --release --dart-define=GEMINI_API_KEY=KUNCI_KAMU`
5. APK: `build/app/outputs/flutter-apk/app-release.apk`

Uji langsung di HP: `flutter run --dart-define=GEMINI_API_KEY=KUNCI_KAMU`

Model AI default: `gemini-3.5-flash`. (`gemini-2.0-flash` sudah dimatikan Google sejak 1 Juni 2026, dan `gemini-2.5-flash` dijadwalkan mati 16 Oktober 2026.) Bila model berganti lagi, tambahkan `--dart-define=GEMINI_MODEL=<nama model>`.

## Catatan
- Kunci API ikut tertanam di APK; cukup untuk tugas kuliah, jangan disebar.
- Alarm memakai notifikasi terjadwal (zona Asia/Jakarta, WIB).
- Alarm: bunyi berulang, notifikasi tidak bisa digeser, layar menyala & kamera dibuka otomatis. Alarm hanya berhenti setelah foto terdeteksi sebagai makanan.
- Jika AI error 2x berturut-turut, muncul opsi memakai foto tanpa analisis (supaya tidak terkunci saat offline).
- Di HP tertentu (Xiaomi/Oppo/Vivo dll) aktifkan "Autostart" dan matikan penghemat baterai untuk MaagMate, serta izinkan "Tampilkan di layar kunci / notifikasi layar penuh".
- Android 12+: izinkan "Alarm & pengingat" untuk MaagMate di pengaturan aplikasi.
- Tombol "Coba alarm (5 detik)" di tab Alarm untuk uji coba.

## Fitur tambahan (v2)
- Beranda: tombol cepat "Catat makan" & "Maag kambuh?", pengingat bila jeda makan terlalu lama.
- Catat: sesuaikan porsi (setengah/normal/banyak/dobel) dan ubah nama makanan sebelum disimpan.
- Riwayat: "Makanan yang sering menyertai keluhan" (pola dari catatanmu, bukan diagnosis), ubah nama makanan, dan tombol "Salin ringkasan 14 hari" untuk ditunjukkan ke dokter.
- Alarm: panduan pengaturan HP agar alarm tidak terlewat.
- Maag Kambuh?: tambahan tips pencegahan dan kapan sebaiknya periksa ke dokter.
- AI: batas waktu 40 detik dan pesan error yang jelas (tanpa internet, kuota habis, model tidak ditemukan).
- Perbaikan: Beranda/Riwayat kini memuat ulang data setelah alarm selesai.

## Update v3
- Kamera: sekarang kamera langsung di dalam app (paket `camera`), bukan lagi pemilih file/dokumen. Ada tombol ganti kamera depan/belakang. Di web, kamera butuh https atau localhost + izin browser. Kalau CameraX bermasalah di Android, ada tombol cadangan "Pakai kamera bawaan HP".
- Alarm bunyi → layar alarm terbuka dan kamera langsung kebuka. Kalau kamera ditutup, tombol "Foto makanan" masih ada.
- Lagu alarm: tab Alarm → kartu "Lagu alarm". Ada 6 lagu bawaan (Alarm Klasik, Ode to Joy, Für Elise, Twinkle Twinkle, Lonceng Pagi, Beep Digital), bisa didengarkan dulu, dan bisa tambah lagu sendiri dari HP (mp3/wav/m4a, maks 20 MB). Lagu sendiri disalin ke penyimpanan app, jadi tetap ada walau file aslinya dihapus. Di web, lagu tambahan hilang saat refresh.
- Bunyi bawaan notifikasi dihentikan begitu layar alarm terbuka, supaya tidak bertabrakan dengan lagu pilihan.
- Package baru: `camera`, `file_picker`, `path_provider`. Jalankan `./setup.sh` lagi (menambah izin CAMERA ke AndroidManifest + `flutter pub get`).
