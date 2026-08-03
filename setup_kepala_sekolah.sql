-- ==============================================================================
-- SETUP AKUN KEPALA SEKOLAH (Sri Wahyuningsih, S.s., S.Pd.)
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
    ('wahyu', crypt('admin54321', gen_salt('bf'))),
    ('kepsek', crypt('admin54321', gen_salt('bf')))
ON CONFLICT (role) DO UPDATE
    SET password_hash = EXCLUDED.password_hash,
        updated_at    = NOW();
