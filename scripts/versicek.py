#!/usr/bin/env python3
"""
Nomor versi APK: sejalan di dua berkas, dan BELUM pernah diunggah.

KENAPA PEMERIKSA INI ADA

Tiga kali dalam dua minggu build ditolak Play Console dengan "Kode versi 28
sudah digunakan" — dan ketiganya baru ketahuan SESUDAH `flutter build
appbundle` selesai, yaitu sesudah menunggu build yang paling lama di
seluruh rantai ini. Bukan kesalahan yang perlu mahal.

DUA HAL YANG DIPERIKSA

1. `pubspec.yaml` dan `android/local.properties` MENYEBUT VERSI YANG SAMA.

   Gradle memakai `flutter.versionCode`/`flutter.versionName` dari
   `local.properties` bila ada, dan MENGABAIKAN `version:` di pubspec.
   Jadi keduanya dapat berselisih tanpa satu pun galat: yang dibaca orang
   di pubspec bukan yang tercetak di APK-nya.

2. NOMORNYA LEBIH BESAR DARIPADA YANG TERAKHIR DIUNGGAH.

   Tidak ada cara menanyakannya ke Play Console tanpa kredensial, dan
   kredensial Play tidak boleh tinggal di repo. Jadi angkanya dicatat
   tangan di `play/terakhir-diunggah.txt`, DIPERBARUI SAAT MENGUNGGAH.

   Catatan rilis sengaja TIDAK dipakai sebagai penandanya, meski menggoda:
   catatan ditulis ketika build disiapkan, bukan sesudah diunggah — jadi
   berkasnya sudah ada justru pada build yang belum terbit, dan
   pemeriksanya akan menolak build yang benar. (Dicoba, dan persis itu
   yang terjadi.)

   Yang masih diperiksa dari catatan rilis: tidak boleh ada catatan untuk
   kode yang LEBIH BESAR daripada versi repo — itu tanda nomornya lupa
   dinaikkan sesudah catatannya ditulis.

CARA PAKAI

    python3 scripts/versicek.py

Dijalankan SEBELUM `flutter build`, bukan sesudah.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

AKAR = Path(__file__).resolve().parents[1]
PUBSPEC = AKAR / "pubspec.yaml"
LOKAL = AKAR / "android" / "local.properties"
CATATAN = AKAR / "play" / "catatan-rilis"


def _versi_pubspec() -> tuple[str, int] | None:
    m = re.search(r"^version:\s*([0-9.]+)\+(\d+)\s*$", PUBSPEC.read_text(encoding="utf-8"), re.M)
    return (m.group(1), int(m.group(2))) if m else None


def _versi_lokal() -> tuple[str | None, int | None]:
    if not LOKAL.exists():
        return (None, None)
    isi = LOKAL.read_text(encoding="utf-8")
    nama = re.search(r"^flutter\.versionName\s*=\s*(.+?)\s*$", isi, re.M)
    kode = re.search(r"^flutter\.versionCode\s*=\s*(\d+)\s*$", isi, re.M)
    return (nama.group(1) if nama else None, int(kode.group(1)) if kode else None)


def _terakhir_diunggah() -> int | None:
    """Angka pada `play/terakhir-diunggah.txt`, atau None bila tidak ada."""
    berkas = AKAR / "play" / "terakhir-diunggah.txt"
    if not berkas.exists():
        return None
    for baris in berkas.read_text(encoding="utf-8").splitlines():
        baris = baris.strip()
        if baris and not baris.startswith("#"):
            return int(baris) if baris.isdigit() else None
    return None


def _kode_terbit() -> list[tuple[int, str]]:
    """(kode, nama berkas) tiap catatan rilis yang ada."""
    if not CATATAN.is_dir():
        return []
    hasil = []
    for berkas in CATATAN.glob("*.txt"):
        m = re.match(r"^[0-9.]+\+(\d+)$", berkas.stem)
        if m:
            hasil.append((int(m.group(1)), berkas.name))
    return sorted(hasil)


def periksa() -> list[str]:
    masalah: list[str] = []

    pub = _versi_pubspec()
    if pub is None:
        return ["pubspec.yaml: baris `version: X.Y.Z+N` tidak terbaca"]
    nama_pub, kode_pub = pub

    nama_lok, kode_lok = _versi_lokal()
    if kode_lok is None:
        masalah.append(
            "android/local.properties: `flutter.versionCode` tidak ada — "
            "Gradle akan memakai pubspec, dan keduanya tidak lagi saling menjaga"
        )
    elif kode_lok != kode_pub:
        masalah.append(
            f"kode versi BERSELISIH: pubspec {kode_pub}, local.properties "
            f"{kode_lok} — yang tercetak di APK adalah {kode_lok}"
        )
    if nama_lok is not None and nama_lok != nama_pub:
        masalah.append(
            f"nama versi BERSELISIH: pubspec {nama_pub}, local.properties {nama_lok}"
        )

    diunggah = _terakhir_diunggah()
    if diunggah is None:
        masalah.append(
            "play/terakhir-diunggah.txt tidak ada atau tidak berisi angka — "
            "tanpa itu tidak ada yang tahu kode mana yang sudah terpakai"
        )
    elif kode_pub <= diunggah:
        masalah.append(
            f"kode versi {kode_pub} TIDAK LEBIH BESAR daripada yang terakhir "
            f"diunggah ({diunggah}) — Play Console akan menolaknya; "
            f"naikkan ke {diunggah + 1}"
        )

    terbit = _kode_terbit()
    lebih = [b for k, b in terbit if k > kode_pub]
    if lebih:
        masalah.append(
            f"ada catatan rilis untuk kode di atas versi repo ({', '.join(lebih)}) — "
            "nomornya lupa dinaikkan?"
        )
    return masalah


if __name__ == "__main__":
    try:
        hasil = periksa()
    except Exception as e:  # noqa: BLE001
        print(f"versi: pemeriksa gagal — {e}")
        sys.exit(2)

    pub = _versi_pubspec()
    diunggah = _terakhir_diunggah()
    catatan = f"repo {pub[0]}+{pub[1]}" if pub else "repo tidak terbaca"
    if diunggah is not None:
        catatan += f", terakhir diunggah +{diunggah}"
    print(f"versi APK: {len(hasil)} masalah ({catatan})")
    if hasil:
        print()
        for x in hasil:
            print(f"  {x}")
    sys.exit(1 if hasil else 0)
