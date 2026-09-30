-- ==============================================================================
-- Hapus/cabut RPC lama yang bisa dipanggil anon TANPA token staf (2026-09-30).
-- Bagian atas sudah dijalankan di project tknvnlyxipxjkospcpbt. Aman dijalankan ulang.
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

-- ------------------------------------------------------------------------------
-- Tambahan 2026-09-30 (debugging ke-2): akses tabel yang terbuka lagi.
-- ------------------------------------------------------------------------------

-- settings: RLS mati & anon bisa INSERT/UPDATE/DELETE -> siapa pun bisa memindah
-- geofence. Kunci ulang seperti setup_rls_hardening_v2.sql blok D. Halaman hanya
-- membaca (SELECT); tulis lewat RPC update_geofence (bertoken).
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL    ON public.settings FROM anon, authenticated;
GRANT  SELECT ON public.settings TO   anon, authenticated;
DROP POLICY IF EXISTS "settings_readable" ON public.settings;
CREATE POLICY "settings_readable" ON public.settings FOR SELECT USING (true);

-- teachers: anon bisa baca hash password & ubah/hapus data guru. Tidak dipakai
-- aplikasi ini (dikonfirmasi user). teachers_safe = view SECURITY DEFINER di atasnya.
DROP POLICY IF EXISTS teachers_select ON public.teachers;
DROP POLICY IF EXISTS teachers_insert ON public.teachers;
DROP POLICY IF EXISTS teachers_update ON public.teachers;
DROP POLICY IF EXISTS teachers_delete ON public.teachers;
REVOKE ALL ON public.teachers      FROM anon, authenticated;
REVOKE ALL ON public.teachers_safe FROM anon, authenticated;

-- sintadu_teachers: app SINTADU sudah tidak dipakai (dikonfirmasi user). RLS tanpa
-- policy = tertutup untuk anon; data tetap ada (password plaintext, jangan dipakai lagi).
ALTER TABLE public.sintadu_teachers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sintadu_teachers FROM anon, authenticated;
