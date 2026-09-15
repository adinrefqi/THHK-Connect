# Project Context — THHK Connect

> Catatan kerja agar pekerjaan bisa dilanjutkan kapan saja (boleh istirahat di tengah jalan).
> Terakhir diperbarui: 2026-09-15

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
- Daftar username admin tertulis ulang di 5 tempat (`index.html` ×2, `admin_dashboard.html`, `rekap.html`, `tugas_titipan.html`) — saat menambah admin, update semuanya.

Perlindungan data bergantung pada `is_valid_staff_token` + RLS di Supabase. Jika kelak butuh data khusus admin: buat akun staf per-user dengan role di DB dan cek role di RPC.

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

## 📌 Status Task Tracker

1. ✅ Fix index.html light-mode invisible text — DONE
2. ✅ Dark/Light mode toggle — DONE (all pages)
3. ✅ Morys superuser access — DONE
4. ✅ Verify & cleanup — DONE
5. ✅ Superadmin Sunedi & Thevea — DONE
6. ✅ Arsipkan halaman buku induk (`guru.html`, `print_induk.html`) — DONE
7. ✅ Rapikan file sisa audit + `.gitignore` — DONE
8. ⏸️ Auth staf per-user dengan role di DB — DITUNDA (risiko diterima)

---

## 🧭 Catatan Teknis

- Tema default: **Dark Mode** di semua halaman aktif
- Tema disimpan di: `localStorage.getItem('theme')`
- Toggle button ada di header setiap halaman
- Semantic colors (emerald, amber, rose, indigo) dibiarkan hardcoded karena masuk akal di kedua tema
