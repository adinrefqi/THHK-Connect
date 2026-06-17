-- ==============================================================================
-- PENGAMANAN RLS — PUTARAN KRITIS
-- ------------------------------------------------------------------------------
-- Menutup dua lubang terparah:
--   #2  Tabel settings (lokasi geofence) bisa diubah siapa saja  -> dikunci
--   #4  reset_device_siswa & proses_absen_piket tanpa cek hak    -> diberi gerbang
--
-- Mekanisme: TOKEN SESI STAF. Saat admin/piket login dgn sandi benar, server
-- menerbitkan token acak berumur 12 jam (disimpan client di localStorage).
-- Semua aksi sensitif minta token ini, bukan sandi mentah.
--
-- PRASYARAT: setup_staff_auth.sql sudah dijalankan (butuh verify_staff_password
-- dan ekstensi pgcrypto).
--
-- CARA PAKAI: jalankan SELURUH file ini SATU KALI di Supabase > SQL Editor,
-- lalu LANGSUNG deploy file HTML terbaru (lihat catatan urutan deploy).
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Tabel sesi staf. RLS aktif & TANPA policy => anon tidak bisa membacanya.
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_sessions (
    token      TEXT PRIMARY KEY,
    role       TEXT NOT NULL,           -- 'admin' | 'piket'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE public.staff_sessions ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- 2. Buat sesi staf setelah verifikasi sandi. Mengembalikan token, atau NULL
--    jika sandi salah. gen_random_bytes berada di schema 'extensions' (pgcrypto).
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_staff_session(
    p_role     TEXT,
    p_password TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_token TEXT;
BEGIN
    IF NOT public.verify_staff_password(p_role, p_password) THEN
        RETURN NULL;
    END IF;

    v_token := encode(gen_random_bytes(24), 'hex');

    INSERT INTO public.staff_sessions (token, role, expires_at)
    VALUES (v_token, p_role, NOW() + INTERVAL '12 hours');

    -- Bersihkan sesi kedaluwarsa sekalian (housekeeping ringan)
    DELETE FROM public.staff_sessions WHERE expires_at < NOW();

    RETURN v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_staff_session(TEXT, TEXT) TO anon, authenticated;

-- ------------------------------------------------------------------------------
-- 3. Helper internal: apakah token valid (belum kedaluwarsa)?
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_valid_staff_token(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.staff_sessions
        WHERE token = p_token AND expires_at > NOW()
    );
END;
$$;

-- ==============================================================================
-- 4. KUNCI TABEL settings (lokasi geofence)
-- ------------------------------------------------------------------------------
-- Sebelumnya: RLS mati + GRANT ALL ke anon => siapa pun bisa memindah lokasi
-- sekolah dan melumpuhkan geofencing. Sekarang: hanya boleh DIBACA langsung;
-- perubahan wajib lewat update_geofence() yang bergerbang token.
-- ==============================================================================
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

REVOKE ALL    ON public.settings FROM anon, authenticated;
GRANT  SELECT ON public.settings TO   anon, authenticated;

DROP POLICY IF EXISTS "settings_readable" ON public.settings;
CREATE POLICY "settings_readable" ON public.settings
    FOR SELECT USING (true);
-- Catatan: tidak ada policy INSERT/UPDATE/DELETE => tulis langsung oleh anon
-- ditolak. proses_absen_siswa (SECURITY DEFINER) tetap bisa membaca settings.

CREATE OR REPLACE FUNCTION public.update_geofence(
    p_token TEXT,
    p_value JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_valid_staff_token(p_token) THEN
        RAISE EXCEPTION 'Tidak diizinkan: sesi staf tidak valid atau kedaluwarsa.';
    END IF;

    INSERT INTO public.settings (key, value, updated_at)
    VALUES ('geofence', p_value, NOW())
    ON CONFLICT (key) DO UPDATE
        SET value = EXCLUDED.value, updated_at = NOW();

    RETURN json_build_object('status', 'success');
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_geofence(TEXT, JSONB) TO anon, authenticated;

-- ==============================================================================
-- 5. GERBANG reset_device_siswa  (#4)
-- ------------------------------------------------------------------------------
-- Tanda tangan lama (UUID) DIHAPUS agar tidak bisa lagi dipanggil tanpa token.
-- ==============================================================================
DROP FUNCTION IF EXISTS public.reset_device_siswa(UUID);

CREATE OR REPLACE FUNCTION public.reset_device_siswa(
    p_student_id UUID,
    p_token      TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_valid_staff_token(p_token) THEN
        RAISE EXCEPTION 'Tidak diizinkan: sesi staf tidak valid atau kedaluwarsa.';
    END IF;

    UPDATE public.students
    SET device_id = NULL
    WHERE id = p_student_id;

    RETURN json_build_object('status', 'success');
END;
$$;

GRANT EXECUTE ON FUNCTION public.reset_device_siswa(UUID, TEXT) TO anon, authenticated;

-- ==============================================================================
-- 6. GERBANG proses_absen_piket  (#4)
-- ------------------------------------------------------------------------------
-- Tanda tangan lama (UUID, TEXT, TEXT) DIHAPUS; ditambah p_token di akhir.
-- ==============================================================================
DROP FUNCTION IF EXISTS public.proses_absen_piket(UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.proses_absen_piket(
    p_student_id  UUID,
    p_teacher_note TEXT,
    p_status      TEXT,
    p_token       TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_valid_staff_token(p_token) THEN
        RAISE EXCEPTION 'Tidak diizinkan: sesi staf tidak valid atau kedaluwarsa.';
    END IF;

    INSERT INTO public.attendance_logs (user_id, latitude, longitude, device_id, status)
    VALUES (p_student_id, NULL, NULL, p_teacher_note, p_status);

    RETURN json_build_object('status', 'success');
END;
$$;

GRANT EXECUTE ON FUNCTION public.proses_absen_piket(UUID, TEXT, TEXT, TEXT) TO anon, authenticated;
