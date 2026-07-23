-- ==============================================================================
-- SETUP AUTENTIKASI STAFF (ADMIN & GURU PIKET) — SERVER-SIDE
-- ------------------------------------------------------------------------------
-- Tujuan: memindahkan verifikasi password admin/piket dari sisi browser
-- (yang terlihat di View Source) ke server, dengan password di-hash (bcrypt).
--
-- CARA PAKAI:
--   1. Buka Supabase Dashboard > SQL Editor.
--   2. Jalankan seluruh isi file ini SATU KALI.
--   3. GANTI password default di bawah ('admin11' & 'admin54321') dengan
--      password baru yang kuat, lalu jalankan ulang bagian INSERT/UPDATE.
-- ==============================================================================

-- Ekstensi untuk hashing password (bcrypt)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Tabel penyimpan hash password per peran. RLS aktif & TANPA policy,
-- sehingga anon key TIDAK bisa membaca isinya sama sekali.
CREATE TABLE IF NOT EXISTS public.staff_credentials (
    role          TEXT PRIMARY KEY,        -- 'admin' atau 'piket'
    password_hash TEXT NOT NULL,
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.staff_credentials ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- Seed password awal (GANTI dengan password kuat sebelum produksi!)
-- crypt(... gen_salt('bf')) menghasilkan hash bcrypt yang tidak bisa dibalik.
-- ------------------------------------------------------------------------------
INSERT INTO public.staff_credentials (role, password_hash) VALUES
    ('admin', crypt('admin11',   gen_salt('bf'))),
    ('piket', crypt('admin54321', gen_salt('bf')))
ON CONFLICT (role) DO UPDATE
    SET password_hash = EXCLUDED.password_hash,
        updated_at    = NOW();

-- ------------------------------------------------------------------------------
-- RPC: verifikasi password. Dipanggil dari client; hanya mengembalikan
-- true/false — hash tidak pernah keluar dari server.
-- SECURITY DEFINER agar bisa membaca staff_credentials meski RLS aktif.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_staff_password(
    p_role     TEXT,
    p_password TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
-- pgcrypto (crypt/gen_salt) berada di schema 'extensions' pada Supabase,
-- jadi keduanya harus disertakan di search_path.
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

    -- crypt(input, hash) menghasilkan hash yang sama hanya jika password cocok
    RETURN v_hash = crypt(p_password, v_hash);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_staff_password(TEXT, TEXT) TO anon, authenticated;

-- ------------------------------------------------------------------------------
-- RPC: Backward compatibility untuk verify_admin_login
-- ------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.verify_admin_login(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.verify_admin_login(TEXT);

CREATE OR REPLACE FUNCTION public.verify_admin_login(
    input_password TEXT,
    input_username TEXT DEFAULT 'admin'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    RETURN public.verify_staff_password('admin', input_password);
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_admin_login(TEXT, TEXT) TO anon, authenticated;

-- ------------------------------------------------------------------------------
-- Cara mengganti password di kemudian hari (jalankan manual saat dibutuhkan):
--
--   UPDATE public.staff_credentials
--   SET password_hash = crypt('PASSWORD_BARU', gen_salt('bf')), updated_at = NOW()
--   WHERE role = 'admin';
-- ------------------------------------------------------------------------------
