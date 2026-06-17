@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo    Upload THHK Connect ke GitHub
echo ============================================
echo.

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Folder ini bukan repo git. Pastikan file .bat berada di folder project.
  echo.
  pause
  exit /b 1
)

set "pesan="
set /p "pesan=Tulis pesan perubahan lalu Enter (kosongkan = pakai tanggal otomatis): "
if "%pesan%"=="" set "pesan=Update %date% %time%"

echo.
echo [1/3] Menambahkan semua perubahan...
git add -A

echo [2/3] Menyimpan (commit)...
git commit -m "%pesan%"
if errorlevel 1 (
  echo      ^(Tidak ada perubahan baru untuk disimpan - lanjut push commit yang belum naik^)
)

echo [3/3] Mengunggah ke GitHub...
git push
if errorlevel 1 (
  echo.
  echo ============================================
  echo    GAGAL mengunggah.
  echo    Cek: koneksi internet, atau login GitHub.
  echo ============================================
  echo.
  pause
  exit /b 1
)

echo.
echo ============================================
echo    SELESAI! Perubahan sudah naik ke GitHub.
echo ============================================
echo.
pause
