# TerraBot Field

Aplikasi Android lapangan PT Alpha Konstruksi Nusantara: **absensi kru** dan
**log pengecoran bored pile**. Offline-first — dapat dipakai seharian di
lokasi tanpa sinyal; semua yang dicatat terkirim sendiri begitu ada sinyal.

Backend: TerraBot (`Terra Nusa Teknologi Office Backend`), rute `/field/*`.
Rancangan lengkap: dokumen project `claude/RANCANGAN-TERRABOT-FIELD-2026-10-07.md`.

Mulai dari [BACA-DULU.md](BACA-DULU.md).

## Struktur

    lib/
      main.dart, app.dart, rute.dart
      inti/
        db/          drift: Induk (data server), Dokumen (antrean), Foto, MetaLokal
        jaringan/    Dio + penyegaran token lintas-isolate
        sinkron/     mesin sinkron (kirim → foto → tarik) + workmanager
        perangkat/   lokasi, kamera+wajah, jam monoton, notifikasi
        sesi/        token, pengguna, peta izin
        tema/, widget/   token warna & komponen dari TerraBot web
        penyedia.dart    provider Riverpod
      fitur/
        masuk/ beranda/ absensi/ pekerja/ pengecoran/ antrean/ pengaturan/
        pengecoran/hitung/   volume, keadaan cor, rencana potong tremie (murni, diuji)
    packages/jam_monoton/    plugin Android: elapsedRealtime + BOOT_COUNT
    test/

## Prinsip

* HP membuat uuid; menyimpan = menaikkan versi; antrean = `versi > versiTerkirim`.
* Isi dokumen = PERSIS skema server (`extra="forbid"`). Jangan tambah bidang lokal di isi.
* Server yang memutuskan: jarak, jam terpercaya, penanda curang, hitungan cor.
  Angka di HP hanya untuk banner.
* Penjelasan = `BannerTerra`, bukan hint kecil di bawah field.
