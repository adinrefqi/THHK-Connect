-- ==============================================================================
-- SESI UPLOAD PER-USER (dipakai Cloudflare Worker thhk-storage)
-- ------------------------------------------------------------------------------
-- Sebelumnya Worker hanya mengecek satu token bersama yang tertulis di HTML
-- (terbaca lewat View Source). Sekarang Worker menanyakan ke server apakah
-- token milik sesi yang sah:
--   - Staf  : token dari create_staff_session (tabel staff_sessions, 12 jam)
--   - Siswa : token dari create_student_session (tabel student_sessions, 180 hari)
--
-- PRASYARAT: setup_rls_hardening.sql (staff_sessions, is_valid_staff_token)
-- dan login_siswa sudah ada di database.
--
-- CARA PAKAI: jalankan SELURUH file ini di Supabase > SQL Editor. Aman
-- dijalankan ulang; login_siswa TIDAK diubah.
-- ==============================================================================

-- 1. Tabel sesi siswa. RLS aktif & TANPA policy => anon tidak bisa membacanya.
CREATE TABLE IF NOT EXISTS public.student_sessions (
    token      TEXT PRIMARY KEY,
    student_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE public.student_sessions ENABLE ROW LEVEL SECURITY;

-- 2. Terbitkan token sesi siswa. Verifikasi NIS/password memakai login_siswa
--    yang sudah ada (melempar exception jika salah), jadi aturannya sama persis.
CREATE OR REPLACE FUNCTION public.create_student_session(
    p_nis      TEXT,
    p_password TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_student JSON;
    v_token   TEXT;
BEGIN
    v_student := public.login_siswa(p_nis, p_password);

    v_token := encode(gen_random_bytes(24), 'hex');

    INSERT INTO public.student_sessions (token, student_id, expires_at)
    VALUES (v_token, (v_student->>'id')::UUID, NOW() + INTERVAL '180 days');

    -- Bersihkan sesi kedaluwarsa sekalian (housekeeping ringan)
    DELETE FROM public.student_sessions WHERE expires_at < NOW();

    RETURN v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_student_session(TEXT, TEXT) TO anon, authenticated;

-- 3. Dipanggil Worker: apakah token milik sesi staf/siswa yang masih berlaku?
--    Hanya mengembalikan true/false; token acak 48 hex tak bisa ditebak.
CREATE OR REPLACE FUNCTION public.verify_upload_token(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_token IS NULL OR p_token = '' THEN
        RETURN FALSE;
    END IF;

    RETURN public.is_valid_staff_token(p_token)
        OR EXISTS (
            SELECT 1 FROM public.student_sessions
            WHERE token = p_token AND expires_at > NOW()
        );
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_upload_token(TEXT) TO anon, authenticated;
