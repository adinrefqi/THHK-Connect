# Project Context — THHK Connect

> Catatan kerja agar pekerjaan bisa dilanjutkan kapan saja (boleh istirahat di tengah jalan).
> Terakhir diperbarui: 2026-06-23

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
| `guru.html` | ✅ Done | Light |
| `admin.html` | ✅ Already had it | Dark |

### Icon Toggle
- Dark mode aktif → ☀️ (sun icon, click untuk switch ke light)
- Light mode aktif → 🌙 (moon icon, click untuk switch ke dark)

---

## 🎯 Fitur Baru: User Morys Superuser

User "morys" dijadikan superuser seperti "adin".

### Perubahan di `index.html`

1. Login check diubah dari:
```javascript
if (nis.toLowerCase() === 'adin') {
    showToast('Selamat datang, Admin Adin!', 'success');
    setView('admin-hub');
} else {
    window.location.href = 'guru_piket.html';
}
```

2. Menjadi:
```javascript
if (['adin', 'morys'].includes(nis.toLowerCase())) {
    const isAdin = nis.toLowerCase() === 'adin';
    showToast('Selamat datang, Admin ' + (isAdin ? 'Adin' : 'Morys') + '!', 'success');
    setView('admin-hub');
    const adminGreeting = document.getElementById('admin-greeting');
    if (adminGreeting) {
        adminGreeting.innerText = 'Halo, ' + (isAdin ? 'Adin' : 'Morys') + ' 👋';
    }
} else {
    window.location.href = 'guru_piket.html';
}
```

### Akses yang Dimiliki Morys
- ✅ Admin Hub
- ✅ Dasbor Guru Piket
- ✅ Admin Dashboard
- ✅ Rekap Absensi
- ✅ Tugas Titipan Guru

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

---

## 🧭 Catatan Teknis

- Tema default: **Dark Mode** (kecuali guru.html yang default Light)
- Tema disimpan di: `localStorage.getItem('theme')`
- Toggle button ada di header setiap halaman
- Semantic colors (emerald, amber, rose, indigo) dibiarkan hardcoded karena masuk akal di kedua tema
