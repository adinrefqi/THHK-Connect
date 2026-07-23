-- ==============================================================================
-- FIX SEPENUHNYA: PASSWORD ADMIN -> admin11 & AKUN ADMIN UNTUK SEMUA TABEL
-- Jalankan seluruh script ini di SUPABASE SQL EDITOR
-- ==============================================================================

-- 1. EXTENSION FOR BCRYPT
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. TABEL STAFF CREDENTIALS (ADMIN & PIKET)
CREATE TABLE IF NOT EXISTS public.staff_credentials (
    role          TEXT PRIMARY KEY,
    password_hash TEXT NOT NULL,
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.staff_credentials ENABLE ROW LEVEL SECURITY;

-- Set password admin menjadi 'admin11' (bcrypt hash)
INSERT INTO public.staff_credentials (role, password_hash) VALUES
    ('admin', crypt('admin11',   gen_salt('bf'))),
    ('piket', crypt('admin54321', gen_salt('bf')))
ON CONFLICT (role) DO UPDATE
    SET password_hash = crypt('admin11', gen_salt('bf')),
        updated_at    = NOW();

-- 3. JIKA ADA TABEL sintadu_teachers (Presensi GTT / Sintadu)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'sintadu_teachers' AND column_name = 'username'
    ) THEN
        EXECUTE 'INSERT INTO public.sintadu_teachers (username, name, password) VALUES (''admin'', ''Administrator'', ''admin11'') ON CONFLICT (username) DO UPDATE SET password = ''admin11''';
    END IF;
END $$;

-- 4. DYNAMIC DROP FUNGSI LAMA (Bebas dari Error 42P13)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN 
        SELECT p.oid::regprocedure AS func_sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE p.proname IN ('verify_staff_password', 'verify_admin_login')
          AND n.nspname = 'public'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.func_sig || ' CASCADE';
    END LOOP;
END $$;

-- 5. FUNGSI VERIFY_STAFF_PASSWORD
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
        RETURN FALSE;
    END IF;

    RETURN v_hash = crypt(p_password, v_hash);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_staff_password(TEXT, TEXT) TO anon, authenticated;

-- 6. FUNGSI VERIFY_ADMIN_LOGIN
CREATE OR REPLACE FUNCTION public.verify_admin_login(
    input_password TEXT DEFAULT NULL,
    input_username TEXT DEFAULT 'admin',
    p_password TEXT DEFAULT NULL,
    p_username TEXT DEFAULT NULL,
    password TEXT DEFAULT NULL,
    username TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_pass TEXT;
BEGIN
    v_pass := COALESCE(input_password, p_password, password);
    IF v_pass IS NULL THEN
        RETURN FALSE;
    END IF;
    RETURN public.verify_staff_password('admin', v_pass);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_admin_login(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- 7. TABEL SETTINGS & GEOFENCE
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'settings'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'key'
        ) THEN
            EXECUTE 'ALTER TABLE public.settings RENAME TO settings_old';
        END IF;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.settings (
    key VARCHAR(50) PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO public.settings (key, value)
VALUES ('geofence', '{"latitude": -6.858194, "longitude": 109.137222, "radius_meters": 50.0}'::jsonb)
ON CONFLICT (key) DO NOTHING;

GRANT ALL ON public.settings TO anon;
GRANT ALL ON public.settings TO authenticated;
GRANT ALL ON public.settings TO service_role;
ALTER TABLE public.settings DISABLE ROW LEVEL SECURITY;

-- VERIFIKASI AKUN ADMIN
SELECT * FROM public.staff_credentials WHERE role = 'admin';
