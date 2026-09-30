# Project Context — THHK Connect

> Catatan kerja agar pekerjaan bisa dilanjutkan kapan saja (boleh istirahat di tengah jalan).
> Terakhir diperbarui: 2026-09-30

---

## 🎯 Fitur Baru: Dark/Light Mode Toggle

User meminta agar aplikasi bisa berganti tema (dark/light) sesuai keinginan pengguna.

### Implementasi

1. **CSS Variables System** — Semua warna didefinisikan sebagai CSS custom properties di `:root` (dark) dan `[data-theme="light"]`
2. **JavaScript Toggle** — Fungsi `initTheme()`, `toggleTheme()`, `updateThemeIcon()` di setiap halaman
3. **Theme Toggle Button** — Tombol di header setiap halaman dengan icon Sun/Moon
4. **Persistence** — Preferensi tema disimpan di `localStorage.setItem('theme', 'dark'|'light')`

### CSS Variables yang Digunakan

```css
:root {
    --bg-primary, --bg-secondary
    --glass-bg, --glass-border, --glass-shadow
    --input-bg, --input-border
    --text-primary, --text-secondary, --text-muted
    --accent, --accent-light
    --header-bg, --divider
    --scrollbar-thumb, --scrollbar-thumb-hover
}
```

### File yang Dimodifikasi

| File | Status | Default Theme |
|------|--------|--------------|
| `index.html` | ✅ Done | Dark |
| `guru_piket.html` | ✅ Done | Dark |
| `admin_dashboard.html` | ✅ Done | Dark |
| `rekap.html` | ✅ Done | Dark |
| `tugas_titipan.html` | ✅ Done | Dark |
| `admin.html` | ✅ Already had it | Dark |

> `guru.html` (default Light) sudah diarsipkan ke `_archive/` — lihat bagian "Pembersihan 2026-09-15".

### Icon Toggle
- Dark mode aktif → ☀️ (sun icon, click untuk switch ke light)
- Light mode aktif → 🌙 (moon icon, click untuk switch ke dark)

---

## 🎯 Fitur Baru: User Superadmin (Adin, Morys, Sunedi, Thevea)

User "morys", "sunedi", dan "thevea" dijadikan superadmin / superuser seperti "adin".

### Perubahan di `index.html`, `admin_dashboard.html`, `rekap.html`, `tugas_titipan.html`

1. Cek sesi & login diubah menjadi:
```javascript
if (['adin', 'morys', 'sunedi', 'thevea', 'wahyu'].includes(nis.toLowerCase())) {
    const isSuperAdmin = ['adin', 'morys', 'sunedi', 'thevea'].includes(userLower);
    const nameMap = { adin: 'Adin', morys: 'Morys', sunedi: 'Sunedi', thevea: 'Thevea', wahyu: 'Bu Sri Wahyuningsih' };
    const nameStr = nameMap[userLower] || (userLower.charAt(0).toUpperCase() + userLower.slice(1));
    const roleTitle = isSuperAdmin ? ('Admin ' + nameStr) : 'Kepala Sekolah (Bu Sri Wahyuningsih)';
    showToast('Selamat datang, ' + roleTitle + '!', 'success');
    setView('admin-hub');
    const adminGreeting = document.getElementById('admin-greeting');
    if (adminGreeting) {
        adminGreeting.innerText = 'Halo, ' + nameStr + ' 👋';
    }
}
```

### Akses Superadmin (Adin, Morys, Sunedi, Thevea)
- ✅ Admin Hub (`index.html`)
- ✅ Dasbor Guru Piket (`guru_piket.html`)
- ✅ Admin Dashboard (`admin_dashboard.html`)
- ✅ Rekap Absensi (`rekap.html`)
- ✅ Tugas Titipan Guru (`tugas_titipan.html`)

---

## 🧹 Pembersihan 2026-09-15

### Halaman buku induk diarsipkan
`guru.html` & `print_induk.html` dipindah ke `_archive/` (tidak di-track git):
- Tabel `buku_induk` **tidak ada** di project Supabase mana pun (dicek via REST → `PGRST205`).
- `guru.html` butuh `localStorage.bi_session` yang tidak pernah di-set lagi oleh aplikasi.
- Tidak ada halaman yang menautkan ke kedua file ini.
- `print_habit.html` masih punya fallback query ke `buku_induk` — aman, error diabaikan.

Jika fitur buku induk mau dihidupkan lagi: buat tabel `buku_induk` di project aktif, isi data ulang, lalu pulihkan file dari `_archive/`.

### File sisa audit diarsipkan
14 screenshot `_audit_*.png` + `_probe.cjs`, `_darkcheck.cjs`, `_lightcheck.cjs` dipindah ke `_archive/`.
`.gitignore` kini mengabaikan `_audit_*.png`, `_*.cjs`, dan `.commandcode/`.

### Project Supabase
Semua halaman aktif memakai project **`tknvnlyxipxjkospcpbt`**. Tabel `students` sudah menolak akses anon (RLS hardening aktif).

### ⚠️ Risiko yang sengaja diterima (keputusan user)
Karena semua guru dipercaya, hal berikut **dibiarkan**:
- Fallback password hardcoded (`admin54321` / `admin11`) di `index.html` & `guru_piket.html`.
- Satu password bersama untuk semua staf; role (superadmin / kepsek / piket) ditentukan dari **username di client** + `localStorage.piket_session`, bukan dari database.
- Daftar username admin tertulis ulang di 6 tempat (`index.html` ×2, `admin_dashboard.html`, `rekap.html`, `tugas_titipan.html`, `guru_piket.html` → `updateBackToPortal`) — saat menambah admin, update semuanya.

Perlindungan data bergantung pada `is_valid_staff_token` + RLS di Supabase. Jika kelak butuh data khusus admin: buat akun staf per-user dengan role di DB dan cek role di RPC.

---

## 🐛 Perbaikan Bug 2026-09-15

Audit bug seluruh aplikasi → 20 temuan, 19 diperbaiki dalam 3 commit (`0234023`, `5923411`, `27a19b5`).

### Kritis
| # | Masalah | Perbaikan |
|---|---------|-----------|
| 1 | APK Flutter mengirim device ID konstan `FLUTTER_ANDROID_NATIVE` → hanya 1 siswa bisa absen | `index.html` membuat ID acak per-instalasi (`localStorage.device_uuid`) jika ID kosong/konstan; baris ID konstan dihapus dari `main.dart`. Siswa yang terkunci ID lama sudah di-reset via SQL. |
| 2 | Setujui/tolak izin memakai `.update()` langsung (diblokir RLS) | Lewat RPC `update_leave_status` (`create_leave_requests.sql`). 2026-09-29: parameter `p_id` jadi `BIGINT` (id live bigint, bukan uuid), status dibatasi APPROVED/REJECTED, error jika id tak ditemukan; fallback `.update()` dihapus |
| 3 | Izin di-APPROVED sebelum absen tercatat | Absen S/I dicatat dulu, baru status diubah |
| 4 | Tombol "Setujui" rusak jika alasan berisi `'` | Tombol hanya kirim ID; data diambil dari `pendingLeaveMap` |
| 5 | `admin.html` "hari ini" pakai UTC | Rentang WIB (`+07:00`) |
| 6 | Dasbor menghitung log A/S/I staf sebagai Hadir | Hitung dari `status`, log terbaru per siswa |
| 7 | Dropdown tahun hanya 2025–2026 | Dibuat otomatis 2025 → tahun berjalan (`rekap.html`, `admin.html`) |

### Tinggi
| # | Masalah | Perbaikan |
|---|---------|-----------|
| 8 | Ganti Bulan/Tahun di rekap tidak memuat ulang | `onchange` memanggil `fetchData()` |
| 9 | Tombol absen aktif lagi / tertimpa "Area Tidak Valid" | Status "✅ Sudah Absen Hari Ini" dipertahankan |
| 10 | Tanda tangan orang tua putih → kosong saat dicetak | `print_habit.html` `.sig-thumb { filter: brightness(0) }` |
| 11 | Query rekap bulanan bisa kena batas 1000 baris | Filter `.in('user_id', siswa kelas)` + urut `created_at` |
| 12 | `proses_absen_piket` selalu INSERT → absen dobel | `fix_absen_duplikat.sql` (**sudah dijalankan**): update log hari ini jika ada, advisory lock per siswa |
| 13 | XSS dari teks izin/bullying/tugas/tanda tangan | Helper `esc()` / `safeUrl()` di `guru_piket.html`, `tugas_titipan.html`; `escapeHtml` di `print_habit.html` |

### Sedang
| # | Masalah | Perbaikan |
|---|---------|-----------|
| 14 | Realtime bullying tidak pernah jalan (anon tanpa SELECT) | Polling `get_bullying_reports` tiap 30 detik + notifikasi laporan baru |
| 15 | Push notif tidak pernah terkirim (`device_tokens` kosong) | ⏸️ **BELUM** — butuh Firebase Messaging di APK + project Firebase |
| 16 | SQL lama membatalkan hardening bila dijalankan ulang | `fix_presensi_error.sql` & `database_setup.sql` → `_archive/`; `setup_dynamic_geofence.sql` tak lagi `GRANT ALL`/`DISABLE RLS` pada `settings` |
| 17 | Tugas titipan tak muncul setelah login form; hanya tugas pertama | Dimuat saat login, semua tugas ditampilkan |
| 18 | UI geofence pakai jarak dibulatkan, validasi pakai jarak mentah | UI pakai jarak mentah |
| 19 | Upload APK mengirim file cache terakhir, bukan body request | Body diutamakan, cache hanya cadangan (**perlu build ulang APK**) |
| 20 | Kecil-kecil | Tanggal "hari ini" WIB di semua halaman; `admin.html` satu channel realtime + pesan error; guard `section-stats` di `rekap.html` |

### ⚠️ Aturan setelah perbaikan ini
- **Jangan jalankan ulang** `setup_rls_hardening.sql` atau `insert_siswa.sql` — keduanya mengembalikan `proses_absen_piket` versi lama (bisa dobel). Definisi terbaru ada di `fix_absen_duplikat.sql`.
- **Jangan jalankan** file SQL di `_archive/`.
- Overload RPC tanpa token pernah muncul lagi di DB (2026-09-30) — setelah menjalankan SQL lama apa pun, jalankan ulang `hapus_rpc_tanpa_token.sql` dan cek Security Advisor.
- Menandai S/I untuk siswa yang sudah absen H hari itu kini **mengganti** statusnya, bukan menambah baris.
- Data dobel lama tidak dihapus; tampilan rekap memakai log terbaru.

### Sisa kerja
- Push notif (#15).

---

## 🔍 Light Mode Fix (Earlier Work)

### Diagnosis (Akar Masalah)

Aplikasi dibangun **"dark-first"**. Sistem theme sebenarnya sudah benar — memakai
CSS variables (`--text-primary`, dll.) di `:root` (dark) dan `[data-theme="light"]`.
`data-theme` di-set pada elemen `<html>` (documentElement); default = `'dark'`.

**Masalahnya:** banyak warna teks **di-hardcode** untuk latar gelap, mengabaikan sistem variable.

### Yang HARUS tetap berwarna terang (JANGAN diubah jadi gelap):
- Tombol solid berwarna / gradient biru
- 2 modal yang sengaja gelap di kedua mode: `#modal-izin` & `#modal-bullying`
- Bottom navigation `#bottom-nav`

---

## ✅ Sudah Selesai

### index.html — SELESAI & terverifikasi
- Light mode readability fixes (66 → 2 elemen)
- Dark/Light mode toggle implementation
- Morys superuser access

### Semua Halaman HTML
- Dark/Light mode toggle buttons di header
- Theme persistence di localStorage
- Icon toggle (sun/moon) sesuai tema aktif

---

## 📌 Progres (per 2026-09-30)

### ✅ Sudah
1. Fix teks tak terlihat di light mode (`index.html`)
2. Toggle Dark/Light mode di semua halaman
3. Superadmin Adin, Morys, Sunedi, Thevea + akun Kepala Sekolah (wahyu)
4. Arsipkan halaman buku induk (`guru.html`, `print_induk.html`) & file sisa audit, rapikan `.gitignore`
5. Audit bug seluruh aplikasi → bug #1–14 dan #16–20 diperbaiki & di-push (lihat "Perbaikan Bug 2026-09-15")
6. Reset `device_id` siswa yang terkunci ID konstan (`FLUTTER_ANDROID_NATIVE` / `UNKNOWN`) via SQL
7. `fix_absen_duplikat.sql` dijalankan di Supabase
8. SQL berbahaya (`fix_presensi_error.sql`, `database_setup.sql`) diarsipkan ke `_archive/`
9. `project_context.md` diperbarui dengan catatan perbaikan
10. Izin yang disetujui terlambat kini dicatat di **tanggal pengajuan** (WIB): `proses_absen_piket` punya parameter opsional `p_tanggal` (di `fix_absen_duplikat.sql`), `guru_piket.html` mengirim tanggal `created_at` izin
11. Rekap bulanan (`rekap.html`, `admin.html` Rekap & Analisis) memakai rentang bulan dan tanggal **WIB**, benar di perangkat dengan zona waktu apa pun
12. Setujui/tolak izin diperbaiki: `update_leave_status` memakai `p_id BIGINT` (`create_leave_requests.sql` **sudah dijalankan**, versi UUID lama terhapus), di-deploy (`4b70b8c`) & **diuji manual berhasil** (2026-09-29)
13. **Upload worker diamankan** (2026-09-30, `0820463`): cek sesi per-user via RPC `verify_upload_token` (`create_upload_sessions.sql` **sudah dijalankan**), nama file dibuat server (UUID, tak bisa menimpa), batas 20 MB, hanya gambar/PDF tampil inline. Worker di-deploy, upload siswa & admin **diuji berhasil**, Secret `UPLOAD_TOKEN` dihapus → token bersama lama ditolak (401). Siswa yang login sebelum 2026-09-30 diminta login ulang saat upload pertama.
14. **Tampilan laptop/PC** (2026-09-30, `8d159b9`): `index.html` punya blok `@media (min-width: 1024px)` — login 2 kolom, Admin Hub kartu 2×2, dasbor siswa dengan sidebar kiri (nav bawah), beranda & kebiasaan 2 kolom; lebar per view diatur `:has()` pada `.app-container`. `guru_piket.html` melebar (`xl:max-w-7xl`), kartu 3 kolom baru di ≥1536px (di 1366px nama terpotong). Tampilan HP tidak berubah. **Dicek user di laptop: bagus.**
15. **Belum absen & Alpha massal di Guru Piket** (2026-09-30): ringkasan "N dari M siswa belum absen", filter "belum absen saja", tombol "Tandai Alpha semua" (memanggil `proses_absen_piket` status A untuk tiap siswa tanpa log hari ini). Kartu siswa berstatus A punya tombol koreksi H/T/S/I — perlu karena `proses_absen_siswa` menolak absen jika sudah ada log hari itu.
16. **Alpha otomatis 15:00 WIB** (2026-09-30, `setup_auto_alpha.sql` **sudah dijalankan**, job pg_cron `auto-alpha-harian` id 1, `0 8 * * 1-5` UTC): Senin–Jumat, siswa kelas 7/8/9 tanpa log hari itu dicatat A (`device_id = OTOMATIS 15:00`). Dilewati jika tak ada satu pun absen hari itu (dianggap libur). Fungsi `auto_alpha_harian` tidak bisa dipanggil anon. Sekolah libur Sabtu & Minggu (dikonfirmasi user). **Jalan pertama 2026-09-30 15:00: sukses, 36 dari 51 siswa ditandai A** (hanya ~7–16 siswa/hari absen lewat aplikasi). User memutuskan fitur **tetap aktif** apa adanya.
17. **APK 1.0.2 (versionCode 3)** dibangun 2026-09-30 (`build/app/outputs/flutter-apk/app-release.apk`, 44,9 MB, ditandatangani debug keystore laptop ini — sama dengan APK sebelumnya): perbaikan upload (#19), reload WebView otomatis jika app dibuka lagi setelah >30 menit di latar belakang, ikon aplikasi logo sekolah (`flutter_launcher_icons`, adaptive latar putih). GPS kini dikirim tiap 2 dtk tanpa distanceFilter (sebelumnya `distanceFilter: 2` → HP diam = koordinat identik → web menampilkan "Sinyal Statis"). **Diuji di HP (Samsung A52) via adb: status "Jarak 15m – dapat absen" setelah >30 dtk diam.** Peringatan build: AGP 8.7.3 & Kotlin 2.1.0 akan segera tak didukung Flutter (naikkan ke AGP ≥8.11.1, Kotlin ≥2.2.20 kelak).
18. **Peta: CartoDB → OpenStreetMap** (2026-09-30): tile CartoDB kini berisi "API KEY REQUIRED". `index.html` & `admin_dashboard.html` memakai `tile.openstreetmap.org` (maxZoom 19, atribusi "© OpenStreetMap" wajib), tema gelap memakai filter invert pada `.leaflet-tile-pane`.
19. **Guru Piket logout saat sesi staf habis** (2026-09-30, `dad9de3`): token staf berlaku 12 jam; sebelumnya dasbor tetap tampil dengan token kedaluwarsa dan polling bullying gagal diam-diam (error 400 di log). `checkPendingBullyingBadge` (saat buka & tiap 30 dtk) kini mengarahkan ke login jika token ditolak.
20. **RPC tanpa token dicabut** (2026-09-30, `hapus_rpc_tanpa_token.sql` **sudah dijalankan & dicek**): `reset_device_siswa(uuid)` dan `proses_absen_piket(uuid,text,text)` versi lama (siapa pun bisa buka kunci HP / catat absen) dihapus; `update_admin_password`, `upsert_teacher_with_hash`, `verify_teacher_login` (tabel `admins`/`teachers`, tidak dipakai aplikasi ini — dikonfirmasi user) dicabut dari anon/authenticated. Versi bertoken tetap ada.

### ⏳ Belum
1. **Pastikan aplikasi yang dipakai siswa sebelum menyebar APK 1.0.2.** Di HP user ada dua app: `com.finansial.thhkconnect` v1.1 (lama, dipasang 31 Mei, kode TIDAK ada di repo ini) dan `com.example.thhk_connect` (Flutter, repo ini). Jika siswa memakai yang lama, APK Flutter terpasang sebagai app KEDUA (bukan update) → ID perangkat berbeda → kemungkinan harus reset kunci HP siswa.
2. **Push notif via Firebase (#15)** — pasang Firebase Messaging di APK (`google-services.json`), panggil `register_device_token`; butuh project Firebase.
6. **Data absen dobel lama** tidak dihapus (rekap sudah memakai log terbaru) — opsional dibersihkan.
7. **Uji manual** perbaikan di browser & HP (belum dilakukan setelah deploy): absen H lalu S untuk siswa sama, cetak laporan kebiasaan, rekap ganti bulan.

### ⏸️ Ditunda (keputusan user)
- Auth staf per-user dengan role di DB (risiko password bersama diterima)

---

## 🧭 Catatan Teknis

- Tema default: **Dark Mode** di semua halaman aktif
- `leave_requests.id` di DB live bertipe **bigint** (bukan uuid) — RPC yang menerima id izin harus `BIGINT`
- Tema disimpan di: `localStorage.getItem('theme')`
- Toggle button ada di header setiap halaman
- Semantic colors (emerald, amber, rose, indigo) dibiarkan hardcoded karena masuk akal di kedua tema
