import '../../core/util/format.dart';

/// KEDALAMAN vs WAKTU untuk satu log bor.
///
/// Pengeboran tercatat sebagai deret bacaan ber-jam. Satu angka kedalaman
/// akhir tidak menjawab pertanyaan yang sebenarnya dibawa ke rapat — "titik
/// ini kok lama", "berhentinya di kedalaman berapa", "lajunya turun mulai
/// jam berapa" — dan deret itulah jawabannya.
///
/// SATU LAWAN SATU dengan `helpers/bor-kurva.helper.ts` di aplikasi web.
/// Keempat angka ringkasannya dibaca orang yang sama, bergantian di dua
/// layar; dua rumus yang berbeda tipis akan menghasilkan dua laporan yang
/// bertentangan tentang titik yang sama, dan tidak ada yang dapat
/// menentukan mana yang benar.
///
/// SELURUHNYA FUNGSI MURNI. Yang salah di sini tidak menimbulkan galat:
/// kurvanya tetap tergambar, rapi dan meyakinkan, dengan bentuk yang salah
/// — dan tidak ada apa pun di layar yang menandainya.

/// Satu bacaan yang dapat digambar.
class TitikKurvaBor {
  const TitikKurvaBor({required this.waktu, required this.dalam, required this.asal});

  /// Milidetik sejak epoch — sumbu X waktu, bukan nomor urut.
  final int waktu;

  /// Meter, selalu angka.
  final double dalam;

  /// Bacaan ASLINYA, supaya yang membaca kurvanya dapat kembali ke barisnya.
  final Map<String, Object?> asal;
}

/// Satu ruas antara dua bacaan berurutan.
class RuasBor {
  const RuasBor({
    required this.dariWaktu,
    required this.sampaiWaktu,
    required this.deltaM,
    required this.jam,
    required this.lajuMPerJam,
  });

  final int dariWaktu;
  final int sampaiWaktu;

  /// Meter yang bertambah pada ruas ini; negatif berarti bacaannya mundur.
  final double deltaM;

  /// Jam yang berlalu. Selalu > 0 — ruas berdurasi nol tidak dibuat.
  final double jam;
  final double lajuMPerJam;
}

class RingkasBor {
  const RingkasBor({
    this.mulai,
    this.selesai,
    this.durasiJam,
    this.kedalamanM,
    this.lajuRataMPerJam,
    this.ruasTerlambat,
    required this.jumlahBacaan,
  });

  final int? mulai;
  final int? selesai;

  /// Jam dari bacaan pertama ke terakhir. `null` bila bacaannya < 2.
  final double? durasiJam;

  /// Kedalaman TERDALAM yang pernah terbaca, bukan bacaan terakhir.
  final double? kedalamanM;

  /// Rerata keseluruhan: kedalaman akhir dibagi durasi.
  final double? lajuRataMPerJam;

  /// Ruas paling lambat — di sinilah pengeboran tertahan.
  final RuasBor? ruasTerlambat;
  final int jumlahBacaan;
}

/// Satu baris pada daftar bacaan di bawah kurvanya.
class BarisBacaan {
  const BarisBacaan({
    required this.bacaan,
    required this.tergambar,
    this.waktu,
    this.dalam,
    this.deltaM,
    this.jam,
    this.lajuMPerJam,
  });

  final Map<String, Object?> bacaan;

  /// `false` berarti jam atau kedalamannya tidak terbaca. Barisnya TETAP
  /// ditampilkan — lihat [barisBacaan].
  final bool tergambar;
  final int? waktu;
  final double? dalam;

  /// Meter yang bertambah dari bacaan sebelumnya; `null` pada yang pertama.
  final double? deltaM;
  final double? jam;

  /// Meter per jam pada ruas ini; `null` bila durasinya nol.
  final double? lajuMPerJam;
}

const _satuJamMs = 3600000.0;

/// Bacaan yang dapat digambar, TERURUT MENURUT WAKTU.
///
/// Dua hal yang masing-masing merusak kurvanya tanpa bersuara:
///
///   * bacaan yang jamnya tidak terbaca. Dijadikan 0 — yang paling
///     menggoda — ia mendarat di 1 Januari 1970, dan seluruh sumbu waktu
///     terentang lima puluh tahun sehingga pengeboran sehari menjadi satu
///     garis tegak di tepi kanan. Dibuang;
///   * bacaan yang urutannya tidak menurut waktu. Server memang
///     memulangkannya terurut, TETAPI satu bacaan yang jamnya baru
///     dibetulkan dapat jatuh di antara dua bacaan lain. Garis yang
///     mengikuti urutan daftar lalu berbalik ke kiri — bentuk yang mustahil
///     dan tetap tergambar.
List<TitikKurvaBor> titikKurvaBor(List<Map<String, Object?>> bacaan) {
  final titik = <TitikKurvaBor>[];
  for (final b in bacaan) {
    final jam = b['at'] == null ? null : DateTime.tryParse('${b['at']}');
    final dalam = toDoubleOrNull(b['depthM']);
    if (jam == null || dalam == null) continue;
    titik.add(TitikKurvaBor(waktu: jam.millisecondsSinceEpoch, dalam: dalam, asal: b));
  }
  titik.sort((a, b) => a.waktu.compareTo(b.waktu));
  return titik;
}

/// Laju per ruas, meter per jam.
///
/// Ruas berdurasi NOL dilewati, bukan dibagi. Dua bacaan berjam sama
/// menghasilkan pembagian dengan nol: `Infinity` pada kurvanya menjadi
/// sumbu yang terentang sampai tak hingga dan seluruh ruas lain menjadi
/// garis datar di nol.
List<RuasBor> ruasBor(List<TitikKurvaBor> titik) {
  final ruas = <RuasBor>[];
  for (var i = 1; i < titik.length; i++) {
    final a = titik[i - 1];
    final b = titik[i];
    final jam = (b.waktu - a.waktu) / _satuJamMs;
    if (jam <= 0) continue;
    final deltaM = b.dalam - a.dalam;
    ruas.add(RuasBor(
      dariWaktu: a.waktu,
      sampaiWaktu: b.waktu,
      deltaM: deltaM,
      jam: jam,
      lajuMPerJam: deltaM / jam,
    ));
  }
  return ruas;
}

/// Angka ringkasan di atas kurvanya.
///
/// [RingkasBor.kedalamanM] memakai yang TERDALAM, bukan bacaan terakhir.
/// Bacaan terakhir bisa lebih dangkal — bor diangkat lalu dibaca lagi — dan
/// menyebutnya sebagai kedalaman lubang membuat laporan menyatakan lubang
/// yang lebih pendek daripada yang sebenarnya dibor.
RingkasBor ringkasBor(List<Map<String, Object?>> bacaan) {
  final titik = titikKurvaBor(bacaan);
  if (titik.isEmpty) return const RingkasBor(jumlahBacaan: 0);

  final mulai = titik.first.waktu;
  final selesai = titik.last.waktu;
  final kedalamanM = titik.map((t) => t.dalam).reduce((a, b) => a > b ? a : b);
  final durasiJam = titik.length > 1 ? (selesai - mulai) / _satuJamMs : null;

  // Ruas MUNDUR tidak ikut dicari yang terlambat.
  //
  // Bor yang diangkat menghasilkan laju negatif, dan negatif selalu lebih
  // kecil daripada ruas paling lambat yang sebenarnya — "paling lambat"
  // akan selalu menunjuk saat bornya diangkat, bukan saat ia tertahan.
  final maju = ruasBor(titik).where((r) => r.deltaM > 0).toList();
  final ruasTerlambat = maju.isEmpty
      ? null
      : maju.reduce((a, b) => b.lajuMPerJam < a.lajuMPerJam ? b : a);

  return RingkasBor(
    mulai: mulai,
    selesai: selesai,
    durasiJam: durasiJam,
    kedalamanM: kedalamanM,
    lajuRataMPerJam:
        durasiJam != null && durasiJam > 0 ? kedalamanM / durasiJam : null,
    ruasTerlambat: ruasTerlambat,
    jumlahBacaan: titik.length,
  );
}

/// Bacaan sebagai BARIS DAFTAR — seluruhnya, termasuk yang tidak tergambar.
///
/// KENAPA YANG TIDAK TERGAMBAR IKUT, dan ini seluruh gunanya.
///
/// [titikKurvaBor] membuang bacaan yang jam atau kedalamannya tidak
/// terbaca; itu benar untuk KURVANYA. Tetapi daftar yang ikut membuangnya
/// menyembunyikan justru baris yang paling perlu dibetulkan: bacaan rusak
/// itu tidak akan pernah muncul di layar mana pun, sehingga tidak ada yang
/// dapat membetulkannya, dan kedalaman akhir titik itu diam-diam tetap
/// salah.
///
/// Urutannya: yang tergambar lebih dulu, MENURUT WAKTU — sama dengan
/// kurvanya, supaya kolom selisih di sebelahnya berarti. Yang tidak
/// tergambar menyusul apa adanya, sebab tidak ada urutan waktu yang dapat
/// diberikan kepadanya.
List<BarisBacaan> barisBacaan(List<Map<String, Object?>> bacaan) {
  final titik = titikKurvaBor(bacaan);
  // Dibandingkan menurut IDENTITAS, bukan menurut kode hash: dua bacaan
  // yang isinya kebetulan sama akan berbagi kode hash, dan yang kedua akan
  // dianggap sudah tergambar lalu hilang dari daftar — padahal daftar ini
  // ada justru supaya tidak ada bacaan yang tak terlihat di mana pun.
  final tergambar = [for (final t in titik) t.asal];

  final baris = <BarisBacaan>[];
  for (var i = 0; i < titik.length; i++) {
    final t = titik[i];
    final sebelum = i > 0 ? titik[i - 1] : null;
    final deltaM = sebelum == null ? null : t.dalam - sebelum.dalam;
    final jam = sebelum == null ? null : (t.waktu - sebelum.waktu) / _satuJamMs;
    baris.add(BarisBacaan(
      bacaan: t.asal,
      tergambar: true,
      waktu: t.waktu,
      dalam: t.dalam,
      deltaM: deltaM,
      jam: jam,
      // Ruas berdurasi nol TIDAK dibagi. Dua bacaan berjam sama
      // menghasilkan tak hingga, yang di kolom laju tampil sebagai angka
      // yang terbaca sebagai pengeboran tercepat yang pernah terjadi,
      // bukan sebagai jam yang salah ketik.
      lajuMPerJam:
          deltaM != null && jam != null && jam > 0 ? deltaM / jam : null,
    ));
  }

  for (final b in bacaan) {
    if (tergambar.any((x) => identical(x, b))) continue;
    baris.add(BarisBacaan(bacaan: b, tergambar: false));
  }
  return baris;
}
