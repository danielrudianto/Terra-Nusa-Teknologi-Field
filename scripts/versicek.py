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

3. ADA BUILD YANG BELUM TERCATAT TERUNGGAH.

   Nomor 2 hanya sebaik catatan tangannya, dan 21-22 Okt 2026 catatan itu
   meleset dua kali: build +37 dibuat dan diunggah, berkasnya tetap
   tertulis 36, dan keesokan harinya pemeriksa ini berkata "0 masalah"
   untuk kode yang sudah terpakai. Play Console yang menolaknya — lagi,
   sesudah build selesai, yaitu persis kegagalan yang pemeriksa ini ada
   untuk mencegahnya.

   Jadi hasil build SETEMPAT ikut dibaca: kode versi tertinggi yang pernah
   dibangun di folder `build/`. Bila kode itu lebih besar daripada yang
   tercatat terunggah, ada build yang nasibnya tidak diketahui — mungkin
   sudah naik ke Play dan lupa dicatat, mungkin dibatalkan. Keduanya perlu
   dijawab orang, dan pemeriksa ini TIDAK dapat menebaknya.

   Karena itu ia PENGINGAT, bukan masalah: "sudah pernah dibangun tetapi
   belum diunggah" adalah keadaan yang sah (build gagal, build diulang),
   dan menggagalkan pemeriksaan karenanya akan mengajari orang
   mengabaikannya.

CARA PAKAI

    python3 scripts/versicek.py                  # sebelum `flutter build`
    python3 scripts/versicek.py --sudah-unggah   # SESUDAH unggah ke Play

`--sudah-unggah` menuliskan kode versi repo ke
`play/terakhir-diunggah.txt`. Itu ada supaya tidak ada lagi angka yang
perlu diketik tangan ke dalam berkas: langkah yang harus diingat manusia
adalah langkah yang suatu hari terlewat — dan dua kali sudah.
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


def _kode_terbangun() -> tuple[int, str] | None:
    """
    (kode versi tertinggi yang pernah dibangun setempat, tanggalnya).

    Dibaca dari `output-metadata.json` yang ditulis Gradle di bawah
    `build/`. Jalurnya persisnya berubah antar versi AGP, jadi yang dicari
    berkas BERNAMA itu di mana pun ia berada, bukan satu jalur tetap —
    pemeriksa yang mati diam-diam karena jalurnya bergeser lebih buruk
    daripada pemeriksa yang tidak ada.

    None bila tidak ada hasil build sama sekali (klon baru, `flutter
    clean`). Itu bukan masalah: tidak tahu berbeda dari tahu-tidak-ada.
    """
    import json
    from datetime import datetime

    akar_build = AKAR / "build"
    if not akar_build.is_dir():
        return None
    tertinggi: int | None = None
    waktu: float | None = None
    for berkas in akar_build.rglob("output-metadata.json"):
        try:
            isi = json.loads(berkas.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            continue
        for unsur in isi.get("elements") or []:
            kode = unsur.get("versionCode")
            if isinstance(kode, int) and (tertinggi is None or kode > tertinggi):
                tertinggi = kode
                try:
                    waktu = berkas.stat().st_mtime
                except OSError:
                    waktu = None
    if tertinggi is None:
        return None
    kapan = (
        datetime.fromtimestamp(waktu).strftime("%d %b %Y %H:%M")
        if waktu
        else "waktu tidak terbaca"
    )
    return (tertinggi, kapan)


def pengingat() -> list[str]:
    """
    Hal yang perlu DIJAWAB ORANG, bukan kegagalan.

    Dipisahkan dari `periksa()` dengan sengaja: yang di sini tidak
    menggagalkan apa pun, sebab keadaannya sah. Yang tidak sah adalah
    membiarkannya tidak terjawab.
    """
    pesan: list[str] = []
    pub = _versi_pubspec()
    terbangun = _kode_terbangun()
    diunggah = _terakhir_diunggah()
    if pub is None or terbangun is None or diunggah is None:
        return pesan
    kode_bangun, kapan = terbangun
    if kode_bangun > diunggah:
        pesan.append(
            f"kode {kode_bangun} pernah DIBANGUN di sini ({kapan}) tetapi "
            f"tercatat belum diunggah (terakhir +{diunggah}).\n"
            f"    Kalau sudah naik ke Play: python scripts/versicek.py --sudah-unggah\n"
            f"    Kalau batal: abaikan pesan ini."
        )
    return pesan


def tandai_sudah_unggah() -> int:
    """Tuliskan kode versi repo ke `play/terakhir-diunggah.txt`."""
    pub = _versi_pubspec()
    if pub is None:
        print("versi: pubspec.yaml tidak terbaca")
        return 2
    kode = pub[1]
    lama = _terakhir_diunggah()
    if lama is not None and kode < lama:
        print(
            f"versi: kode repo ({kode}) LEBIH KECIL daripada yang tercatat "
            f"terunggah (+{lama}). Tidak ditulis — periksa dulu yang benar."
        )
        return 2
    berkas = AKAR / "play" / "terakhir-diunggah.txt"
    baris = berkas.read_text(encoding="utf-8").splitlines() if berkas.exists() else []
    # Keterangan di atasnya DIPERTAHANKAN; yang diganti hanya angkanya.
    keluar, tertulis = [], False
    for b in baris:
        if not tertulis and b.strip() and not b.strip().startswith("#"):
            keluar.append(str(kode))
            tertulis = True
        else:
            keluar.append(b)
    if not tertulis:
        keluar.append(str(kode))
    berkas.write_text("\n".join(keluar).rstrip() + "\n", encoding="utf-8")
    print(f"versi: tercatat +{kode} sudah diunggah" + (f" (sebelumnya +{lama})" if lama is not None else ""))
    return 0


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
    if "--sudah-unggah" in sys.argv:
        sys.exit(tandai_sudah_unggah())

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

    # PENGINGAT dicetak walau tidak ada masalah — justru di situlah ia
    # berguna: 22 Okt 2026 pemeriksa ini berkata "0 masalah" untuk kode
    # yang sudah terpakai di Play.
    try:
        for x in pengingat():
            print()
            print(f"  [?] {x}")
    except Exception as e:  # noqa: BLE001
        print(f"  (pengingat build tidak terbaca: {e})")

    sys.exit(1 if hasil else 0)
