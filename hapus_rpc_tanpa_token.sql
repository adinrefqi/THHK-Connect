-- ==============================================================================
-- Hapus/cabut RPC lama yang bisa dipanggil anon TANPA token staf (2026-09-30).
-- Sudah dijalankan di project tknvnlyxipxjkospcpbt. Aman dijalankan ulang.
--
-- Semua halaman memakai versi bertoken:
--   reset_device_siswa(uuid, text), proses_absen_piket(uuid, text, text, text, date)
-- Overload tanpa token ini muncul lagi (kemungkinan dari SQL lama) dan membuat
-- siapa pun bisa membuka kunci HP siswa / mencatat absen siswa mana pun.
-- ==============================================================================

DROP FUNCTION IF EXISTS public.reset_device_siswa(UUID);
DROP FUNCTION IF EXISTS public.proses_absen_piket(UUID, TEXT, TEXT);

-- Tabel admins/teachers tidak dipakai aplikasi ini (dikonfirmasi user).
-- Fungsi dibiarkan ada; kembalikan dengan GRANT EXECUTE ... TO anon jika perlu.
REVOKE EXECUTE ON FUNCTION public.update_admin_password(VARCHAR, VARCHAR) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.upsert_teacher_with_hash(VARCHAR, VARCHAR, VARCHAR, NUMERIC, NUMERIC, VARCHAR, VARCHAR) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.verify_teacher_login(TEXT) FROM PUBLIC, anon, authenticated;
