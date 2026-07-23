-- ==============================================================================
-- FIX: Error "column value does not exist" saat presensi
-- 
-- PENYEBAB: Fungsi RPC proses_absen_siswa mencoba SELECT value FROM settings
--           tetapi tabel settings di database belum memiliki kolom key/value.
--
-- JALANKAN SQL INI DI SUPABASE SQL EDITOR
-- ==============================================================================

-- 1. Buat tabel settings (key-value) jika belum ada
--    Jika tabel settings sudah ada dengan skema berbeda, rename dulu:
DO $$
BEGIN
    -- Cek apakah tabel settings ada
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'settings'
    ) THEN
        -- Cek apakah kolom 'key' sudah ada
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' AND table_name = 'settings' AND column_name = 'key'
        ) THEN
            -- Tabel settings ada tapi bukan format key-value
            -- Rename tabel lama agar tidak hilang
            EXECUTE 'ALTER TABLE public.settings RENAME TO settings_old';
            RAISE NOTICE 'Tabel settings lama di-rename ke settings_old';
        END IF;
    END IF;
END $$;

-- 2. Buat tabel settings format key-value (jika belum ada setelah rename)
CREATE TABLE IF NOT EXISTS public.settings (
    key VARCHAR(50) PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Masukkan data geofence default (koordinat SMP THHK Tegal)
INSERT INTO public.settings (key, value)
VALUES ('geofence', '{"latitude": -6.858194, "longitude": 109.137222, "radius_meters": 50.0}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 4. Berikan izin akses
GRANT ALL ON public.settings TO anon;
GRANT ALL ON public.settings TO authenticated;
GRANT ALL ON public.settings TO service_role;

-- 5. Nonaktifkan RLS pada tabel settings agar RPC SECURITY DEFINER bisa akses
ALTER TABLE public.settings DISABLE ROW LEVEL SECURITY;

-- 6. Verifikasi — jalankan query ini untuk memastikan fix berhasil:
-- SELECT * FROM public.settings WHERE key = 'geofence';
