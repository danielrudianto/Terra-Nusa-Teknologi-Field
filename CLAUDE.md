# CLAUDE.md — TerraBot Field (Flutter)

Bahasa kode & komentar: Indonesia (sama dengan backend/frontend TerraBot).

## Wajib

- Isi `Dokumen.isi` harus PERSIS model Pydantic di backend
  `schemas/field_schema.py` (`DataPekerja`, `DataAbsen`, `DataTandaBor`,
  `DataCor`). Server memakai `extra="forbid"`: bidang tambahan = item DITOLAK.
- Angka desimal dikirim sebagai TEKS (`angkaTeks`), waktu sebagai ISO
  berzona (`isoBerzona`). Jangan `toIso8601String()` untuk waktu lokal.
- Jangan menulis tabel `Induk` dari layar — hanya dari tarikan.
- Penyegaran token hanya lewat `KlienApi._segarkan` (kunci lintas-isolate).
  Refresh token sekali pakai; dua penyegaran serentak mencabut seluruh sesi.
- Rakit layanan hanya lewat `KonteksAplikasi.buka()` — dipakai `main()` DAN
  pekerja latar.
- Banner (`BannerTerra`) untuk penjelasan; jangan helperText kecil.
- Ubah tabel drift → naikkan `schemaVersion` + migrasi, lalu
  `dart run build_runner build -d`.

## Uji

    flutter analyze
    flutter test

Logika murni (hitungan cor, rencana potong) di `lib/fitur/pengecoran/hitung/`
wajib punya uji di `test/`.
