# Perle KKN

Aplikasi Android inventaris perlengkapan KKN. Flutter + Supabase, **offline-first**:
semua layar membaca/menulis SQLite di HP, lalu tersinkron ke Supabase saat ada internet.

## Fitur (MVP)

| # | Fitur | Keterangan |
|---|-------|------------|
| 1 | Auth | Email + kata sandi. Pendaftar pertama = admin; berikutnya wajib kode kelompok. |
| 2 | Daftar barang | Nama, kategori, jumlah, status (ada / harus beli / pinjam), sumber, penanggung jawab pembawa. |
| 3 | Checklist packing | Centang per barang, progres, filter "Punya saya" & "Belum". |
| 4 | QR per barang | Label QR (cetak PDF A4), scan → catat pinjam/kembali, riwayat & "siapa memegang apa". |
| 5 | Pengeluaran | Nominal, kategori, foto struk (Supabase Storage), total & subtotal otomatis. |
| 6 | Mobile-friendly | Target sentuh besar, tema terang/gelap, teruji di lebar layar 360 dp. |

## Menyiapkan

1. **Buat project Supabase**, lalu jalankan `supabase/migrations/0001_init.sql` di
   Dashboard → SQL Editor. Skrip ini membuat tabel, aturan akses (RLS), dan bucket `receipts`.
2. (Disarankan) Authentication → Sign In / Providers → Email: matikan **Confirm email**.
   Pengirim email bawaan Supabase sangat dibatasi, sehingga anggota bisa gagal mendaftar
   kalau konfirmasi email dinyalakan.
3. Salin `env.example.json` menjadi `env.json`, isi URL project dan publishable key
   (Project Settings → API Keys). `env.json` tidak ikut ter-commit.
4. Jalankan:

   ```bash
   flutter pub get
   ```

   ```bash
   flutter run --dart-define-from-file=env.json
   ```

   APK untuk dibagikan ke anggota:

   ```bash
   flutter build apk --release --dart-define-from-file=env.json
   ```

5. **Daftar pertama kali dengan akun Anda** (kode kelompok dikosongkan) — akun pertama
   otomatis menjadi admin. Kode untuk anggota ada di *Lainnya → Anggota kelompok*.

Dibangun dengan Flutter 3.50 (Dart 3.14). Android minimum: API 24.

## Peran

| | Admin (koordinator) | Anggota |
|---|---|---|
| Lihat semua data | ✓ | ✓ |
| Tambah/ubah/hapus barang | ✓ | – |
| Centang packing | ✓ (+ kosongkan semua) | ✓ |
| Catat pinjam/kembali | ✓ | ✓ |
| Pengeluaran | semua | tambah; ubah/hapus miliknya sendiri |
| Kode kelompok & peran anggota | ✓ | – |

Aturan ini ditegakkan di server lewat RLS, bukan hanya disembunyikan di tampilan.

## Skema database (Supabase / Postgres)

```
auth.users ─1:1─ profiles(id, full_name, role)            role: admin | anggota
app_config(join_code)                                     satu baris, hanya admin

items(id, name, category, quantity, unit,
      status,                 ada | harus_beli | pinjam
      source,                 milik siapa / dipinjam dari mana
      carrier_id → profiles,  penanggung jawab pembawa (bila punya akun)
      carrier_name,           … atau nama bebas
      notes, created_by, created_at, updated_at, deleted_at)

packing_checks(item_id → items [PK], is_packed, packed_by, packed_at, updated_at)

loan_logs(id, item_id → items, action,  pinjam | kembali
          quantity, person_name, note, occurred_at, recorded_by,
          created_at, updated_at, deleted_at)

expenses(id, description, amount, category, spent_on, paid_by_name,
         receipt_path,          path di bucket Storage "receipts"
         note, created_by, created_at, updated_at, deleted_at)
```

Keputusan desain:

- **Satu project Supabase = satu kelompok KKN.** Tidak ada kolom `group_id`.
- **`id` dibuat di HP (UUID)** supaya baris bisa dibuat saat offline.
- **`updated_at` selalu diisi server** (trigger) dan dipakai sebagai kursor sinkronisasi.
- **Hapus = soft delete** (`deleted_at`) agar penghapusan ikut tersinkron ke HP lain.
- **Jumlah "sedang dipinjam" tidak disimpan**, melainkan dihitung dari log
  (pinjam − kembali), sehingga catatan dari beberapa HP yang offline tidak saling menimpa.
- **Centang packing dipisah dari `items`** supaya anggota bisa mencentang tanpa hak ubah barang.

## Sinkronisasi offline

`lib/core/sync/sync_engine.dart`, dijalankan saat masuk, setelah tiap perubahan, saat
koneksi kembali, saat aplikasi dibuka lagi, dan tiap 2 menit:

1. Unggah foto struk yang belum terunggah.
2. **Push** semua baris lokal bertanda `dirty` (upsert).
3. **Pull** baris server yang `updated_at`-nya melewati kursor.

Konflik: *tulisan terakhir yang menang* per baris. Baris yang ditolak server (mis. tidak
berhak) tidak menghalangi baris lain; jumlahnya tampil di *Lainnya → Sinkronisasi* dan
bisa dibuang dari sana. Ikon awan di pojok kanan atas menunjukkan status dan jumlah
perubahan yang belum terkirim.

Keluar akun menghapus data lokal di HP itu — aplikasi memperingatkan bila masih ada
perubahan yang belum terkirim.

## Struktur folder

```
lib/
  main.dart, app.dart
  core/
    config/     env (URL & key Supabase dari --dart-define)
    db/         skema SQLite lokal + provider
    sync/       mesin sinkron, definisi tabel, akses Supabase, pengendali
    router/     go_router + pengalihan masuk/keluar
    theme/, utils/, widgets/
  features/
    auth/       masuk, daftar, profil & peran
    home/       kerangka 4 tab + tombol Scan
    items/      daftar, detail (QR), formulir barang
    packing/    checklist packing
    loans/      scan QR, lembar pinjam/kembali, riwayat
    qr/         format isi QR + lembar label PDF
    expenses/   pengeluaran + foto struk
    more/       sinkronisasi, anggota, keluar
    data_providers.dart   repository & provider data semua fitur
supabase/
  migrations/0001_init.sql   skema + RLS + bucket Storage
  tests/                     uji RLS di Postgres lokal
test/                        uji sinkron, repository, QR, dan layar
```

## Pengujian

```bash
flutter analyze
```

```bash
flutter test
```

Uji aturan akses database (butuh PostgreSQL terpasang; tidak menyentuh Supabase):

```bash
supabase/tests/run_local.sh
```
