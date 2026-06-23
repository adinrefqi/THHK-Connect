# Project Context — Perbaikan Light Mode THHK Connect

> Catatan kerja agar pekerjaan bisa dilanjutkan kapan saja (boleh istirahat di tengah jalan).
> Terakhir diperbarui: 2026-06-23

---

## 🎯 Tujuan / Permintaan User

Saat aplikasi diganti ke **Light Mode**, banyak teks (font) menjadi **tidak terlihat**.
Tugas: perbaiki agar semua teks terbaca di light mode, **tanpa merusak dark mode**.

---

## 🔍 Diagnosis (Akar Masalah)

Aplikasi dibangun **"dark-first"**. Sistem theme sebenarnya sudah benar — memakai
CSS variables (`--text-primary`, dll.) di `:root` (dark) dan `[data-theme="light"]`.
`data-theme` di-set pada elemen `<html>` (documentElement); default = `'dark'`.

**Masalahnya:** banyak warna teks **di-hardcode** untuk latar gelap, mengabaikan sistem variable:
1. Teks putih hardcoded: `color:#fff`, `color:white`, `rgba(255,255,255,..)` (inline & CSS class)
2. Label aksen biru pucat: class Tailwind `text-blue-200/300`, inline `rgba(147,197,253,..)`, class `.section-label`
3. Status pucat: `text-green-300`, `text-yellow-300`, `text-red-300`, rose `#fda4af/#fca5a5/#fb7185`

Di dark mode → terlihat (terang di atas gelap). Di light mode → terang di atas terang → **hilang**.

### Yang HARUS tetap berwarna terang (JANGAN diubah jadi gelap):
- Tombol solid berwarna / gradient biru (mis. tombol "Masuk ke Sistem", "Kirim Data Kebiasaan")
  → teks putih memang benar di atas biru.
- **2 modal yang sengaja gelap di kedua mode:** `#modal-izin` & `#modal-bullying`
  (latarnya gradient navy `linear-gradient(160deg, rgba(30,64,175..) , rgba(15,23,42..))`).
- **Bottom navigation** `#bottom-nav` (latar navy `rgba(15,27,61,0.88)`).

---

## 🛠️ Pola Solusi (PENTING — pakai pola ini untuk semua file)

Tambahkan **satu blok override CSS** tepat sebelum `</style>`, semua selektor diawali
`[data-theme="light"]`. Karena scoped ke light, **dark mode 100% tidak tersentuh** (nol risiko).

Tiga jenis selektor:
1. **Class utility** → `[data-theme="light"] .text-white { color: var(--text-primary); }` dst.
2. **Inline style** (butuh `!important`) → `[data-theme="light"] [style*="color:#fff"] { color: var(--text-primary) !important; }`
   - WAJIB cover semua variasi spasi: `color:#fff` / `color: #fff` / `rgba(255,255,255` / `rgba(255, 255, 255` / `rgba(147,197,253` / `rgba(147, 197, 253`.
3. **CSS rule komponen** yang set warna container/inherited (mis. `#section-habits`, `.habit-input`, `.mood-label`, `.section-label`) → override per-selektor.

Lalu **blok EXCEPTIONS** (kembalikan ke terang) untuk: tombol gradient/solid, `#modal-izin`,
`#modal-bullying`, `#bottom-nav`.

Palet light yang dipakai (konsisten):
- Teks utama → `var(--text-primary)` (#1e293b)
- Aksen biru → `#1d4ed8` (label), `#2563eb`
- Hijau → `#059669` · Kuning/amber → `#b45309` · Merah/rose → `#dc2626`
- Teks pudar → `rgba(30,41,59,0.4–0.7)`

---

## ✅ Sudah Selesai

### `index.html` — SELESAI & terverifikasi
- Masalah awal: **66** elemen teks tak terlihat di light mode.
- Ditambahkan blok "LIGHT MODE READABILITY OVERRIDES" sebelum `</style>` (sekitar baris 2043+).
- Hasil audit: **66 → 2**, dan 2 sisanya adalah **false positive** (tombol biru "Masuk ke Sistem"
  & "Kirim Data Kebiasaan" — putih-di-atas-gradient-biru, memang BENAR; heuristik tak bisa baca CSS gradient).
- Dark mode dicek: **0** override bocor (`.text-white` tetap putih). Aman total.
- Screenshot light mode login view: tampil benar.

---

## ⏳ Belum Selesai (Langkah Berikutnya)

### TODO 1 — Audit + perbaiki 6 file sisa
Jalankan audit dulu untuk lihat jumlah masalah per file, lalu terapkan pola yang sama:
- `tugas_titipan.html`  (perkiraan: ~7 white inline + class `.section-title`,`.task-teacher`,`.brand-icon svg`,`.fab svg` — banyak `color:white` di CSS class)
- `guru_piket.html`     (~5; ada `.alert-toast` yang justru HARUS tetap putih karena latar warna solid)
- `rekap.html`          (~2 white)
- `admin.html`          (~2; `.tab-btn.active` putih di atas `var(--accent)` → tetap putih)
- `admin_dashboard.html`(grep awal 0 white inline, tetap perlu diaudit untuk pale-blue/status)
- `guru.html`           (2 kasus = tombol `background:var(--accent)`/`#10b981` → teks putih BENAR, kemungkinan sudah aman)

⚠️ Catatan: tiap file punya komponen unik. **Selalu audit dulu** (lihat tool di bawah),
klasifikasikan mana yang harus flip-ke-gelap vs mana yang harus tetap-terang (tombol/toast/badge berwarna).

### TODO 2 — Verifikasi akhir + bersih-bersih
- Re-run audit semua file → target **0 masalah nyata** (abaikan false-positive tombol gradient).
- Re-run dark-check semua file → pastikan 0 override bocor.
- **Hapus file sementara**: `_lightcheck.cjs`, `_darkcheck.cjs`, dan semua `_audit_*.png`.

---

## 🧪 Cara Verifikasi (tool sementara, sudah dibuat di folder project)

Puppeteer sudah tersedia di `node_modules`.

```bash
# Audit light mode (cari teks low-contrast). TAG bebas (mis. before/after).
node _lightcheck.cjs <file.html> after

# Cek dark mode tidak rusak (harus lapor 0)
node _darkcheck.cjs <file.html>
```

- `_lightcheck.cjs`: paksa light mode, buka semua view `.hidden`, hitung teks dgn rasio kontras < 2.0,
  simpan screenshot `_audit_<nama>_<tag>.png`. Memblok jaringan (CDN supabase/leaflet/font) → cepat & offline.
- `_darkcheck.cjs`: paksa dark mode, pastikan `.text-white` tetap `rgb(255,255,255)` (override tak bocor).
- **False positive yang normal:** tombol dengan latar `linear-gradient(...)` dilaporkan low-contrast
  karena heuristik membaca background gradient sebagai putih. Verifikasi manual = teks putih di atas biru = OK.

---

## 📌 Status Task Tracker (internal)
1. ✅ Fix index.html light-mode invisible text — DONE
2. ⏳ Fix remaining HTML files' light mode — IN PROGRESS (belum mulai file lain)
3. ⏳ Verify fixes visually and clean up — PENDING

## 🧭 Saat melanjutkan, mulai dari sini:
1. Jalankan `node _lightcheck.cjs tugas_titipan.html before` (dan file lain) untuk lihat daftar masalah.
2. Terapkan blok override `[data-theme="light"]` sebelum `</style>` tiap file, ikut pola index.html.
3. Hati-hati pada pengecualian per-file (toast, tab aktif, tombol berwarna).
4. Audit ulang sampai 0 masalah nyata, cek dark mode, lalu hapus file `_*.cjs` & `_audit_*.png`.
