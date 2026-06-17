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
| 2 | 🔴 Kritis | RLS database terlalu terbuka (`USING (true)`) | ⏳ Belum |
| 3 | 🟠 Tinggi | Worker `/upload` tanpa autentikasi | ✅ **Diperbaiki** |
| 4 | 🟠 Tinggi | RPC `SECURITY DEFINER` tanpa cek hak akses | ⏳ Belum |

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

## 2. 🔴 RLS database terlalu terbuka — ⏳ BELUM DIPERBAIKI

Beberapa policy mengizinkan SEMUA operasi tanpa batas:

```sql
-- students & attendance_logs (insert_siswa.sql)
CREATE POLICY ... FOR ALL USING (true) WITH CHECK (true);
-- delegated_tasks (create_delegated_tasks.sql)
CREATE POLICY "Allow public delete" ... FOR DELETE USING (true);
-- settings / lokasi geofence (setup_dynamic_geofence.sql)
ALTER TABLE public.settings DISABLE ROW LEVEL SECURITY;
GRANT ALL ON public.settings TO anon;
```

**Dampak:** dengan anon key, siapa pun bisa membaca seluruh data siswa, menghapus/mengubah
log absensi, dan **memindahkan titik lokasi sekolah** sehingga absen bisa dari mana saja.

**Rekomendasi:**
- Ganti policy `USING (true)` dengan kondisi berbasis `auth.uid()` (mis. siswa hanya boleh
  melihat/menulis datanya sendiri).
- Untuk tabel `settings`: aktifkan kembali RLS, beri akses **SELECT** ke anon, tapi **UPDATE**
  hanya lewat fungsi/role admin.
- Hapus policy `FOR DELETE USING (true)` pada `delegated_tasks`.

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

## 4. 🟠 RPC `SECURITY DEFINER` tanpa cek hak akses — ⏳ BELUM DIPERBAIKI

`reset_device_siswa(p_student_id)` dan `proses_absen_piket(...)` (di `database_setup.sql`)
berjalan dengan hak elevasi tetapi **tidak mengecek siapa pemanggilnya**.

**Dampak:** siapa pun dengan anon key bisa membuka kunci device siswa mana saja, atau
**mencatat absen untuk siswa lain tanpa berada di lokasi** (melewati geofencing).

**Rekomendasi:** tambahkan pemeriksaan peran di awal fungsi (mis. verifikasi token/sesi
admin-piket) sebelum menjalankan aksi, atau pindahkan pemanggilan ke jalur yang sudah
terautentikasi.

---

## Prioritas tindak lanjut yang disarankan
1. Deploy perbaikan #1 (jalankan `setup_staff_auth.sql` + ganti password).
2. Perbaiki #3 (worker token) — cepat & berdampak besar.
3. Perketat #2 & #4 (RLS + cek hak akses RPC) — paling berdampak, perlu pengujian menyeluruh.
