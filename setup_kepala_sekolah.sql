-- ==============================================================================
-- SETUP AKUN KEPALA SEKOLAH (Sri Wahyuningsih, S.s., S.Pd.) & AUTENTIKASI STAF
-- ==============================================================================
-- Username: wahyu
-- Password: admin54321
-- Role: Kepala Sekolah / Admin
-- ==============================================================================

-- 1. Buat tabel sintadu_teachers jika belum ada
CREATE TABLE IF NOT EXISTS public.sintadu_teachers (
    username TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    password TEXT NOT NULL,
    subjects TEXT[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 2. Masukkan data ke tabel sintadu_teachers
INSERT INTO public.sintadu_teachers (username, name, password, subjects)
VALUES ('wahyu', 'Sri Wahyuningsih, S.s., S.Pd.', 'admin54321', '{}')
ON CONFLICT (username) DO UPDATE
SET name = EXCLUDED.name,
    password = EXCLUDED.password;

-- 3. Aktifkan ekstensi pgcrypto & buat tabel staff_credentials jika belum ada
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.staff_credentials (
    role          TEXT PRIMARY KEY,
    password_hash TEXT NOT NULL,
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Masukkan hash password ke staff_credentials (Autentikasi Server)
INSERT INTO public.staff_credentials (role, password_hash) VALUES
    ('admin', crypt('admin11',   gen_salt('bf'))),
    ('piket', crypt('admin54321', gen_salt('bf'))),
    ('wahyu', crypt('admin54321', gen_salt('bf'))),
    ('kepsek', crypt('admin54321', gen_salt('bf')))
ON CONFLICT (role) DO UPDATE
    SET password_hash = EXCLUDED.password_hash,
        updated_at    = NOW();

-- 5. Buat tabel staff_sessions jika belum ada
CREATE TABLE IF NOT EXISTS public.staff_sessions (
    token      TEXT PRIMARY KEY,
    role       TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- 6. Buat/perbarui fungsi RPC verifikasi password & sesi staf
CREATE OR REPLACE FUNCTION public.verify_staff_password(
    p_role     TEXT,
    p_password TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_hash TEXT;
BEGIN
    SELECT password_hash INTO v_hash
    FROM public.staff_credentials
    WHERE role = p_role;

    IF v_hash IS NULL THEN
        -- Fallback check ke piket jika role spesifik tidak ditemukan
        SELECT password_hash INTO v_hash
        FROM public.staff_credentials
        WHERE role = 'piket';
    END IF;

    IF v_hash IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN v_hash = crypt(p_password, v_hash);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_staff_password(TEXT, TEXT) TO anon, authenticated;

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

    DELETE FROM public.staff_sessions WHERE expires_at < NOW();

    RETURN v_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_staff_session(TEXT, TEXT) TO anon, authenticated;
