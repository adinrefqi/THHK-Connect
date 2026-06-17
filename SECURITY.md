# Laporan Keamanan — THHK Connect

**Tanggal review:** 17 Juni 2026
**Lingkup:** halaman app (HTML/JS client), Cloudflare Worker, skema database Supabase.

> Inti dari hampir semua temuan: **keamanan dipasang di sisi client (browser), bukan server.**
> Apa pun yang ada di browser bisa dilihat & dimanipulasi oleh pengguna. Penegakan
> keamanan yang sesungguhnya harus terjadi di server (RLS + fungsi RPC Supabase).

---

## Ringkasan Temuan

| # | Tingkat | Masalah | Status |
|---|---------|---------|--------|
| 1 | 🔴 Kritis | Password admin & piket ditulis polos di kode client | ✅ **Diperbaiki** |
| 2 | 🔴 Kritis | RLS database terlalu terbuka (`USING (true)`) | 🟡 **Sebagian** (lihat di bawah) |
| 3 | 🟠 Tinggi | Worker `/upload` tanpa autentikasi | ✅ **Diperbaiki** |
| 4 | 🟠 Tinggi | RPC `SECURITY DEFINER` tanpa cek hak akses | ✅ **Diperbaiki** |

> **Catatan:** Supabase **anon key** yang terlihat di kode itu **normal dan bukan
> kerentanan** — memang dirancang publik. Keamanan bergantung pada RLS di belakangnya (#2).

---

## 1. 🔴 Password admin & piket polos di client — ✅ DIPERBAIKI

**Sebelum:** password dibandingkan langsung di JavaScript:
- `admin.html` → `'admin123'`
- `guru_piket.html` & `index.html` → `'admin54321'`

Siapa pun bisa membuka **View Source** dan langsung mendapat akses penuh.

**Perbaikan yang sudah dilakukan:**
- Dibuat tabel `staff_credentials` + RPC `verify_staff_password()` (lihat `setup_staff_auth.sql`)
  yang menyimpan password sebagai **hash bcrypt** dan hanya mengembalikan `true/false`.
- `admin.html`, `guru_piket.html`, dan `index.html` kini memverifikasi password via RPC,
  bukan perbandingan polos.

**⚠️ LANGKAH WAJIB agar login kembali berfungsi:**
1. Jalankan `setup_staff_auth.sql` di **Supabase > SQL Editor** (satu kali).
2. **Ganti** password default (`admin123`, `admin54321`) dengan password baru yang kuat
   (lihat instruksi di dalam file SQL).

---

## 2. 🔴 RLS database terlalu terbuka — 🟡 SEBAGIAN DIPERBAIKI

Beberapa policy mengizinkan SEMUA operasi tanpa batas (`USING (true)`).

**Dampak:** dengan anon key, siapa pun bisa membaca seluruh data siswa, menghapus/mengubah
log absensi, membaca aduan perundungan, dan **memindahkan titik lokasi sekolah**.

### ⚠️ Kendala arsitektur yang membatasi solusi

App ini memakai **anon key untuk SEMUA akses** dan **tidak memakai Supabase Auth**, sehingga
`auth.uid()` selalu `NULL`. Akibatnya RLS pada tabel yang dibaca **langsung** dari client
tidak bisa membedakan antar-pengguna — policy hanya bisa "izinkan semua anon" atau "tolak
semua anon". **Isolasi per-pengguna sejati hanya mungkin** dengan salah satu dari:
- mengadopsi Supabase Auth (agar `auth.uid()` terisi), atau
- merutekan akses lewat RPC `SECURITY DEFINER` yang memvalidasi sesi siswa / token staf.

### ✅ Yang sudah dikunci

Dijalankan lewat **`setup_rls_hardening.sql`** dan **`setup_rls_hardening_v2.sql`**:

| Tabel | Sebelum | Sesudah |
|---|---|---|
| `settings` (geofence) | RLS off + GRANT ALL anon | RLS on, **SELECT** saja; tulis lewat `update_geofence()` bergerbang token |
| `students` | `FOR ALL USING(true)`; kolom `password` terbaca | **SELECT** saja; tulis ditolak (lewat RPC); kolom `password` **dicabut hak bacanya** |
| `attendance_logs` | `FOR ALL USING(true)` | **SELECT** saja; insert lewat RPC; hapus/ubah langsung ditolak |
| `bullying_reports` | `SELECT/UPDATE USING(true)` (sensitif!) | **INSERT** saja; baca/ubah hanya lewat `get_bullying_reports()` / `update_bullying_status()` bergerbang token |

> Catatan realtime: karena `bullying_reports` kini tidak bisa di-SELECT anon, langganan
> realtime-nya berhenti mengirim event (ini justru menutup kebocoran nama korban via realtime).
> Badge & daftar aduan tetap ter-update saat tab dibuka (via RPC), bukan lagi otomatis.

### ⏳ SISA PEKERJAAN (belum bisa dikunci tanpa migrasi)

| Tabel | Risiko | Kenapa belum | Rekomendasi |
|---|---|---|---|
| `habit_logs` | Antar-siswa bisa baca jurnal & TTD ortu | dibaca/ditulis langsung per-siswa via anon | migrasi ke RPC sesi-siswa (`get_my_habits` / `save_habit`) |
| `leave_requests` | Anon bisa baca semua izin & ubah status | staf baca/ubah langsung tanpa token | RPC bergerbang token (baca/approve/reject) + insert siswa via sesi |
| `delegated_tasks` | Anon bisa insert/ubah/**hapus** tugas | `tugas_titipan.html` & piket akses langsung | RPC bergerbang token; hapus policy `FOR DELETE USING(true)` setelah migrasi |
| `students` (residual) | Nama/kelas/device masih terbaca anon | dipakai dasbor; tak ada `auth.uid()` | hanya tertutup bila pindah ke Supabase Auth / RPC |
| `attendance_logs` (residual) | Riwayat absensi semua siswa terbaca anon | dibaca dasbor & halaman siswa | sda |
| `sintadu_*` | **Tanpa RLS sama sekali** + password guru plaintext | dipakai aplikasi terpisah (tak ada di repo ini) | **prioritas**: aktifkan RLS + hash password + RPC login guru |

---

## 3. 🟠 Worker `/upload` tanpa autentikasi — ✅ DIPERBAIKI

**Sebelum:** `worker.js` membuka `POST /upload` untuk siapa pun (CORS `*`, tanpa token).
Siapa pun bisa meng-upload file apa pun ke bucket R2 dan menyajikannya dari domain kamu.

**Perbaikan yang sudah dilakukan:**
- `worker.js` kini menolak upload (HTTP 401) kecuali request membawa header
  `X-Upload-Token` yang cocok dengan secret `UPLOAD_TOKEN` di Cloudflare.
- `index.html` & `tugas_titipan.html` mengirim token tersebut di setiap upload.

**⚠️ LANGKAH WAJIB agar upload kembali berfungsi:**
1. Buka **Cloudflare Dashboard → Worker `thhk-storage` → Settings → Variables**.
2. Tambah **Secret** baru bernama `UPLOAD_TOKEN` dengan nilai:
   `e11a81b52fa2cf7b979189d525f7f53217022e289aeac77f`
   (sama persis dengan konstanta `UPLOAD_TOKEN` di kode client).
3. Deploy ulang worker.

**Catatan jujur:** karena app murni client-side, token ini tetap ada di browser dan secara
teori bisa ditemukan orang yang gigih. Ini menaikkan palang dari "siapa saja tanpa usaha"
menjadi "harus sengaja membongkar". Pengamanan paling kuat (*signed upload URL* berjangka
waktu via backend) bisa jadi langkah lanjutan.

---

## 4. 🟠 RPC `SECURITY DEFINER` tanpa cek hak akses — ✅ DIPERBAIKI

`reset_device_siswa(p_student_id)` dan `proses_absen_piket(...)` (di `database_setup.sql`)
dulu berjalan dengan hak elevasi tetapi **tidak mengecek siapa pemanggilnya**.

**Dampak (sebelum):** siapa pun dengan anon key bisa membuka kunci device siswa mana saja,
atau **mencatat absen untuk siswa lain tanpa berada di lokasi** (melewati geofencing).

**Perbaikan yang sudah dilakukan (`setup_rls_hardening.sql`):**
- Tanda tangan lama (tanpa token) **di-`DROP`** sehingga tidak bisa dipanggil lagi.
- Versi baru mewajibkan `p_token` yang divalidasi `is_valid_staff_token()` (sesi staf
  12 jam yang diterbitkan `create_staff_session` setelah verifikasi sandi).
- Client (`admin.html`, `guru_piket.html`, `admin_dashboard.html`) kini mengirim token
  dari `localStorage` di setiap pemanggilan; bila token habis → diminta login ulang.
- RPC tambahan yang juga bergerbang token: `update_geofence`, `get_bullying_reports`,
  `update_bullying_status`.

**⚠️ URUTAN DEPLOY:** jalankan `setup_rls_hardening.sql` **lalu** `setup_rls_hardening_v2.sql`
di Supabase SQL Editor, **baru** deploy file HTML terbaru. (HTML baru mengandalkan tanda
tangan & RPC baru; bila DB belum diperbarui, aksi staf akan error.)

---

## Prioritas tindak lanjut yang disarankan

**Sudah selesai:** #1 (sandi staf server-side), #3 (worker token), #4 (RPC bergerbang token),
dan sebagian besar #2 (kunci `settings`, `students`, `attendance_logs`, `bullying_reports`).

**Wajib sebelum produksi:**
1. Jalankan urutan SQL: `setup_staff_auth.sql` → `setup_rls_hardening.sql` →
   `setup_rls_hardening_v2.sql`, lalu **ganti semua sandi default** (`admin123`, `admin54321`,
   sandi siswa `1234`), baru deploy HTML terbaru.
2. **`sintadu_*`** — aktifkan RLS + hash password guru (saat ini tabel terbuka penuh).

**Langkah lanjutan (butuh migrasi RPC / Supabase Auth):**
3. `habit_logs`, `leave_requests`, `delegated_tasks` — pindahkan ke RPC bergerbang sesi
   agar tidak bisa dibaca/diubah lintas-pengguna (lihat tabel "SISA PEKERJAAN" di #2).
4. Pertimbangkan adopsi **Supabase Auth** agar `auth.uid()` tersedia — ini menyederhanakan
   seluruh RLS dan menutup sisa kebocoran baca pada `students` & `attendance_logs`.
