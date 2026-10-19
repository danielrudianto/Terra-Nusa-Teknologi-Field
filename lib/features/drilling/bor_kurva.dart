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

/// Berapa lama sebuah ruas MANDEK supaya layak disebut "berhenti".
///
/// Dipakai hanya untuk MENCATAT dan MENYOROTI berhentinya — bukan untuk
/// menghitung durasi. Durasi efektif menjumlahkan seluruh ruas yang maju,
/// berapa pun lamanya; ruas mandek lima menit tetap mengurangi durasi
/// efektif, hanya saja tidak pantas disebut "berhenti" di layar.
///
/// Lima belas menit: menyambung pipa dan memindahkan tanah galian memakan
/// waktu, dan bacaan yang kebetulan diambil berapit di antaranya bukan
/// berhenti.
///
/// ANGKANYA SAMA DENGAN WEB (`helpers/bor-kurva.helper.ts`, MENIT_BERHENTI).
/// Dua layar yang menyebut "2 kali berhenti" dan "3 kali berhenti" untuk
/// titik yang sama merusak kepercayaan pada dua-duanya.
const menitBerhenti = 15;

class RingkasBor {
  const RingkasBor({
    this.mulai,
    this.selesai,
    this.durasiJam,
    this.durasiEfektifJam,
    this.durasiBerhentiJam,
    this.berhenti = const [],
    this.kedalamanM,
    this.lajuRataMPerJam,
    this.lajuEfektifMPerJam,
    this.ruasTerlambat,
    required this.jumlahBacaan,
  });

  final int? mulai;
  final int? selesai;

  /// Jam dari bacaan pertama ke terakhir — TERMASUK waktu berhenti.
  /// `null` bila bacaannya < 2.
  final double? durasiJam;

  /// Jam yang benar-benar dipakai MENGEBOR — ruas berhenti tidak dihitung.
  ///
  /// Ruas yang kedalamannya tetap bukan pengeboran, dan ruas yang
  /// kedalamannya BERKURANG (bor diangkat) juga bukan.
  ///
  /// `null` bila bacaannya < 2 — sama seperti durasi total. Nol akan
  /// terbaca "sudah diukur, hasilnya nol", dan itu pernyataan yang berbeda
  /// dari "belum ada yang dapat diukur".
  final double? durasiEfektifJam;

  /// Jam yang hilang karena berhenti. SELALU `durasiJam - durasiEfektifJam`,
  /// dihitung sebagai selisih dan bukan penjumlahan tersendiri — supaya
  /// ketiganya selalu saling menjumlah di layar.
  final double? durasiBerhentiJam;

  /// Ruas berhenti yang LEBIH LAMA dari [menitBerhenti], untuk disebut satu
  /// per satu. Yang lebih pendek tetap mengurangi durasi efektif.
  final List<RuasBor> berhenti;

  /// Kedalaman TERDALAM yang pernah terbaca, bukan bacaan terakhir.
  final double? kedalamanM;

  /// Rerata terhadap durasi TOTAL — termasuk waktu berhenti.
  final double? lajuRataMPerJam;

  /// Rerata terhadap durasi EFEKTIF — laju rig saat benar-benar mengebor.
  final double? lajuEfektifMPerJam;

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

/// Ruas-ruas MANDEK YANG BERURUTAN digabung menjadi SATU berhenti.
///
/// KENAPA — Daniel, 19 Oktober 2026:
///
///     "waktu berhenti gw suka minta engineer update juga. misalkan jam
///      11:00-13:00 dia berhenti, jam 12:00 dia update (dia samain
///      kedalaman bor nya). di app nya dihitung 2 kali berhenti."
///
/// Bacaan di tengah berhenti itu BUKAN kejadian baru — ia justru bukti
/// bahwa berhentinya masih berlangsung. Dihitung apa adanya, satu
/// berhenti dua jam dengan satu bacaan di tengahnya menjadi "2 kali
/// berhenti · masing-masing 1 jam", dan orang yang disiplin mengabarkan
/// keadaan rignya justru tampak paling sering berhenti. Itu kebalikan dari
/// yang hendak diukur, dan ia MENGAJARI kru berhenti mengabarkan.
///
/// Durasi efektif tidak berubah sedikit pun: ia dijumlah dari ruas yang
/// MAJU, dan penggabungan ini hanya menyentuh yang mandek. Jadi identitas
/// `total = efektif + berhenti` tetap berdiri.
///
/// AMBANG 15 MENIT DITERAPKAN SESUDAH DIGABUNG, bukan sebelum: tiga mandek
/// sepuluh menit berturut-turut adalah setengah jam rig diam, dan
/// disaring satu per satu ketiganya lolos tanpa terlihat di mana pun.
///
/// ATURAN INI SAMA DI WEB (`bor-kurva.helper.ts`) DAN SERVER.
List<RuasBor> gabungBerhenti(List<RuasBor> ruas) {
  final hasil = <RuasBor>[];
  var i = 0;
  while (i < ruas.length) {
    if (ruas[i].deltaM > 0) {
      i++;
      continue;
    }
    final mulai = i;
    var jam = 0.0;
    var delta = 0.0;
    while (i < ruas.length && ruas[i].deltaM <= 0) {
      jam += ruas[i].jam;
      delta += ruas[i].deltaM;
      i++;
    }
    if (jam * 60 < menitBerhenti) continue;
    hasil.add(RuasBor(
      dariWaktu: ruas[mulai].dariWaktu,
      sampaiWaktu: ruas[i - 1].sampaiWaktu,
      deltaM: delta,
      jam: jam,
      // Ruas gabungan selalu berdurasi > 0 (tiap ruas asalnya begitu),
      // jadi pembagian ini aman.
      lajuMPerJam: delta / jam,
    ));
  }
  return hasil;
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
  final ruas = ruasBor(titik);
  final maju = ruas.where((r) => r.deltaM > 0).toList();
  final ruasTerlambat = maju.isEmpty
      ? null
      : maju.reduce((a, b) => b.lajuMPerJam < a.lajuMPerJam ? b : a);

  final efektif =
      durasiJam == null ? null : maju.fold<double>(0, (j, r) => j + r.jam);
  final berhenti = gabungBerhenti(ruas);

  return RingkasBor(
    mulai: mulai,
    selesai: selesai,
    durasiJam: durasiJam,
    durasiEfektifJam: efektif,
    // `clamp` TIDAK dipakai: ia dideklarasikan di `num` dan memulangkan
    // `num`, yang tidak dapat diberikan ke `double?` tanpa pemeran.
    durasiBerhentiJam: durasiJam == null || efektif == null
        ? null
        : (durasiJam - efektif < 0 ? 0.0 : durasiJam - efektif),
    berhenti: berhenti,
    kedalamanM: kedalamanM,
    lajuRataMPerJam:
        durasiJam != null && durasiJam > 0 ? kedalamanM / durasiJam : null,
    lajuEfektifMPerJam:
        efektif != null && efektif > 0 ? kedalamanM / efektif : null,
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
