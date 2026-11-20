import 'package:flutter/material.dart';

const kGreen = Color(0xFF0F766E); // primer (teal)
const kDeep = Color(0xFF0B3B36);
const kOrange = Color(0xFFD9822B); // aksen hangat, dipakai hemat
const kBg = Color(0xFFF5F8F7);
const kYellow = Color(0xFFE3A72F);
const kPink = Color(0xFFD0654F);
const kBlue = Color(0xFF3E7BC4);
const kPurple = Color(0xFF5B6AD0);
const kTints = [
  Color(0xFFF1F6F4),
  Color(0xFFEAF3F1),
  Color(0xFFF1F1F8),
  Color(0xFFF8F1EF),
  Color(0xFFEFF4FA),
];

List<Color> mealGradient(String label) {
  final l = label.toLowerCase();
  if (l.contains('sarap') || l.contains('pagi')) {
    return const [Color(0xFFFFFAF0), Color(0xFFFCF1DC)];
  }
  if (l.contains('siang')) return const [Color(0xFFF2FAF8), Color(0xFFE2F2EE)];
  if (l.contains('malam')) return const [Color(0xFFF4F5FC), Color(0xFFE6E9F7)];
  if (l.contains('sore')) return const [Color(0xFFFEF6F2), Color(0xFFF9E6DE)];
  return const [Color(0xFFF4F8F7), Color(0xFFE8F0EE)];
}

const complaintEmoji = {
  'Tidak ada': '😊',
  'Perih': '😣',
  'Mual': '🤢',
  'Kembung': '🎈',
  'Panas di dada': '🔥',
};

String mealEmoji(String label) {
  final l = label.toLowerCase();
  if (l.contains('sarap') || l.contains('pagi')) return '🍳';
  if (l.contains('siang')) return '🍛';
  if (l.contains('malam')) return '🌙';
  if (l.contains('sore')) return '🍪';
  return '🍽️';
}

class MealLog {
  final String id;
  final DateTime time;
  String foods;
  final double carbs, protein, fat, kcal;
  String complaint;
  String? photo; // path foto di HP, null bila tidak ada

  MealLog({
    required this.id,
    required this.time,
    required this.foods,
    required this.carbs,
    required this.protein,
    required this.fat,
    required this.kcal,
    required this.complaint,
    this.photo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'foods': foods,
        'carbs': carbs,
        'protein': protein,
        'fat': fat,
        'kcal': kcal,
        'complaint': complaint,
        'photo': photo,
      };

  factory MealLog.fromJson(Map<String, dynamic> j) => MealLog(
        id: j['id'],
        time: DateTime.parse(j['time']),
        foods: j['foods'],
        carbs: (j['carbs'] as num).toDouble(),
        protein: (j['protein'] as num).toDouble(),
        fat: (j['fat'] as num).toDouble(),
        kcal: (j['kcal'] as num).toDouble(),
        complaint: j['complaint'],
        photo: j['photo'] as String?,
      );
}

class Reminder {
  final int id;
  final int hour, minute;
  final String label;
  final bool on;

  Reminder({
    required this.id,
    required this.hour,
    required this.minute,
    required this.label,
    this.on = true,
  });

  Reminder copyWith({bool? on, int? hour, int? minute}) => Reminder(
      id: id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      label: label,
      on: on ?? this.on);

  String get timeText =>
      '${hour.toString().padLeft(2, '0')}.${minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() =>
      {'id': id, 'hour': hour, 'minute': minute, 'label': label, 'on': on};

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
      id: j['id'],
      hour: j['hour'],
      minute: j['minute'],
      label: j['label'],
      on: j['on']);
}

class Estimate {
  final bool isFood;
  final List<String> foods;
  final double carbs, protein, fat, kcal;
  Estimate(this.isFood, this.foods, this.carbs, this.protein, this.fat, this.kcal);

  /// Salinan dengan porsi dikali [k] (0.5 = setengah) dan/atau nama diganti.
  Estimate scaled(double k, {List<String>? foods}) => Estimate(
      isFood, foods ?? this.foods, carbs * k, protein * k, fat * k, kcal * k);
}

IconData mealIcon(String label) {
  final l = label.toLowerCase();
  if (l.contains('sarap') || l.contains('pagi')) return Icons.free_breakfast_rounded;
  if (l.contains('siang')) return Icons.lunch_dining_rounded;
  if (l.contains('malam')) return Icons.dinner_dining_rounded;
  if (l.contains('sore')) return Icons.cookie_rounded;
  return Icons.restaurant_rounded;
}

IconData complaintIcon(String c) {
  switch (c) {
    case 'Tidak ada':
      return Icons.sentiment_satisfied_rounded;
    case 'Perih':
      return Icons.sentiment_very_dissatisfied_rounded;
    case 'Mual':
      return Icons.sick_rounded;
    case 'Kembung':
      return Icons.bubble_chart_rounded;
    case 'Panas di dada':
      return Icons.local_fire_department_rounded;
    default:
      return Icons.sentiment_neutral_rounded;
  }
}

// ============================================================ Analisis pola
String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _p2(int n) => n.toString().padLeft(2, '0');

Iterable<String> _foodNames(MealLog l) => l.foods
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .where((e) => e.isNotEmpty && e != 'makanan' && !e.contains('tanpa analisis'));

class Trigger {
  final String name;
  final int bad, total;
  Trigger(this.name, this.bad, this.total);
}

/// Makanan yang muncul di >= 2 catatan berkeluhan dan di >= separuh
/// kemunculannya disertai keluhan. Hanya pola dari catatan, bukan diagnosis.
List<Trigger> findTriggers(List<MealLog> logs) {
  final bad = <String, int>{}, total = <String, int>{};
  for (final l in logs) {
    final isBad = l.complaint != 'Tidak ada';
    for (final f in _foodNames(l).toSet()) {
      total[f] = (total[f] ?? 0) + 1;
      if (isBad) bad[f] = (bad[f] ?? 0) + 1;
    }
  }
  final out = <Trigger>[
    for (final e in bad.entries)
      if (e.value >= 2 && e.value * 2 >= total[e.key]!)
        Trigger(e.key, e.value, total[e.key]!)
  ];
  out.sort((a, b) {
    final c = b.bad.compareTo(a.bad);
    return c != 0 ? c : (b.bad / b.total).compareTo(a.bad / a.total);
  });
  return out.take(3).toList();
}

/// Saran pengganti untuk makanan pemicu (berdasarkan kata kunci nama makanan).
/// Hanya saran umum, bukan resep atau diagnosis.
const _swapRules = <(List<String>, String)>[
  (['sambal', 'pedas', 'cabai', 'cabe', 'rawit', 'seblak', 'balado', 'rica'],
      'bumbu yang tidak pedas: tumisan bawang, kecap, atau sup bening'),
  (['goreng', 'gorengan', 'crispy', 'katsu', 'fried', 'nugget', 'tempura'],
      'versi rebus, kukus, atau panggang tanpa banyak minyak'),
  (['santan', 'gulai', 'rendang', 'opor', 'kari', 'soto betawi', 'lemak'],
      'lauk berkuah bening seperti sup atau sayur bening'),
  (['kopi', 'coffee', 'latte', 'cappuccino', 'espresso', 'teh', 'tea'],
      'air putih hangat atau teh herbal tanpa kafein (misalnya jahe)'),
  (['soda', 'cola', 'sprite', 'bersoda', 'boba'],
      'air putih atau air kelapa tanpa soda'),
  (['jeruk', 'lemon', 'asam', 'cuka', 'rujak', 'tomat', 'nanas'],
      'buah yang lebih lembut: pisang atau pepaya'),
  (['mie', 'mi ', 'ramen', 'indomie', 'bakso'],
      'nasi hangat atau bubur dengan lauk sederhana'),
  (['pizza', 'burger', 'keju', 'cheese'],
      'roti tawar atau nasi dengan lauk panggang/rebus'),
];

/// Daftar saran pengganti berdasarkan pemicu. Kosong bila tidak ada yang cocok.
List<String> swapSuggestions(List<Trigger> triggers) {
  final out = <String>[];
  for (final t in triggers) {
    final n = '${t.name.toLowerCase()} ';
    for (final r in _swapRules) {
      if (r.$1.any(n.contains)) {
        out.add('Ganti ${cap(t.name)} dengan ${r.$2}.');
        break;
      }
    }
  }
  return out;
}

/// Pilihan yang umumnya lebih ramah lambung (panduan umum, bukan diagnosis).
const gentleMenu = <String>[
  'Bubur ayam tanpa sambal',
  'Nasi putih dengan ayam atau ikan rebus/kukus',
  'Sup bening dengan sayur lunak',
  'Pisang, pepaya, atau roti tawar',
  'Telur rebus atau tim',
];

/// Teks ringkasan untuk ditunjukkan ke dokter (disalin ke clipboard).
String doctorSummary(List<MealLog> all, {int days = 14}) {
  final since = DateTime.now().subtract(Duration(days: days));
  final logs = all.where((l) => l.time.isAfter(since)).toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  final b = StringBuffer('Ringkasan MaagMate ($days hari terakhir)\n');
  if (logs.isEmpty) {
    b.write('Belum ada catatan makan pada periode ini.');
    return b.toString();
  }
  final bad = logs.where((l) => l.complaint != 'Tidak ada').toList();
  final dayKeys = logs.map((l) => '${l.time.year}-${l.time.month}-${l.time.day}').toSet();
  final kcal = logs.fold<double>(0, (a, l) => a + l.kcal);
  b.writeln('Tercatat ${logs.length} kali makan, ${bad.length} di antaranya disertai keluhan.');
  b.writeln('Rata-rata asupan sekitar ${(kcal / dayKeys.length).round()} kcal/hari (perkiraan AI dari foto).');
  final counts = <String, int>{};
  for (final l in bad) {
    counts[l.complaint] = (counts[l.complaint] ?? 0) + 1;
  }
  if (counts.isNotEmpty) {
    b.writeln('Keluhan: ${counts.entries.map((e) => '${e.key} ${e.value}x').join(', ')}.');
  }
  final t = findTriggers(logs);
  if (t.isNotEmpty) {
    b.writeln('Makanan yang sering menyertai keluhan: ${t.map((x) => '${cap(x.name)} (${x.bad} dari ${x.total} kali makan)').join(', ')}.');
  }
  if (bad.isNotEmpty) {
    b.writeln('\nCatatan keluhan:');
    for (final l in bad) {
      b.writeln('- ${l.time.day}/${l.time.month} ${_p2(l.time.hour)}.${_p2(l.time.minute)}: ${l.foods.isEmpty ? 'makanan tidak dicatat' : l.foods} -> ${l.complaint}');
    }
  }
  b.write('\nCatatan: angka gizi hanya perkiraan dari foto dan ini bukan diagnosis.');
  return b.toString();
}