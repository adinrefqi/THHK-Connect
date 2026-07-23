-- ==============================================================================
-- 1. Buat Tabel settings Jika Belum Ada
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.settings (
    key VARCHAR(50) PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Masukkan data awal geofence sekolah (default: SMP THHK Tegal)
INSERT INTO public.settings (key, value)
VALUES ('geofence', '{"latitude": -6.858194, "longitude": 109.137222, "radius_meters": 50.0}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Berikan izin akses select/update bagi peran anon/authenticated
GRANT ALL ON public.settings TO anon;
GRANT ALL ON public.settings TO authenticated;
GRANT ALL ON public.settings TO service_role;

-- Enable RLS if needed, but for simplicity let's bypass RLS on settings or add open policies
ALTER TABLE public.settings DISABLE ROW LEVEL SECURITY;

-- ==============================================================================
-- 2. Modifikasi Fungsi Absen Siswa Agar Membaca Geofence dari Tabel settings
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.proses_absen_siswa(
    p_user_id UUID,
    p_lat FLOAT8,
    p_lon FLOAT8,
    p_device_id TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student RECORD;
    v_distance FLOAT8;
    v_geofence JSONB;
    v_target_lat FLOAT8;
    v_target_lon FLOAT8;
    v_max_radius FLOAT8;
    v_status VARCHAR(1) := 'H';
    v_now_wib TIMESTAMP;
    v_today_start TIMESTAMPTZ;
    v_today_end TIMESTAMPTZ;
BEGIN
    -- 1. Ambil data siswa
    SELECT id, device_id INTO v_student FROM public.students WHERE id = p_user_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Siswa tidak ditemukan dalam database';
    END IF;

    -- 1b. Cek duplikasi: apakah siswa sudah absen hari ini (zona WIB)?
    v_now_wib := NOW() AT TIME ZONE 'Asia/Jakarta';
    v_today_start := (v_now_wib::date)::timestamp AT TIME ZONE 'Asia/Jakarta';
    v_today_end := v_today_start + INTERVAL '1 day';

    IF EXISTS (
        SELECT 1 FROM public.attendance_logs
        WHERE user_id = p_user_id
          AND created_at >= v_today_start
          AND created_at < v_today_end
    ) THEN
        RAISE EXCEPTION 'Anda sudah melakukan presensi hari ini.';
    END IF;

    -- 2. Validasi Device Binding
    IF v_student.device_id IS NULL THEN
        -- Cek apakah device sudah dipakai siswa lain
        IF EXISTS (SELECT 1 FROM public.students WHERE device_id = p_device_id AND id != p_user_id) THEN
            RAISE EXCEPTION 'HP ini sudah terdaftar atas nama siswa lain';
        END IF;
        -- Kunci device ke siswa ini
        UPDATE public.students SET device_id = p_device_id WHERE id = p_user_id;
    ELSE
        -- Cocokkan device
        IF v_student.device_id != p_device_id THEN
            RAISE EXCEPTION 'Anda harus menggunakan HP yang sudah terdaftar. Hubungi admin untuk reset.';
        END IF;
    END IF;

    -- 3. Ambil Pengaturan Geofence dari Database secara Dinamis
    SELECT value INTO v_geofence FROM public.settings WHERE key = 'geofence';
    
    IF v_geofence IS NOT NULL THEN
        v_target_lat := (v_geofence->>'latitude')::FLOAT8;
        v_target_lon := (v_geofence->>'longitude')::FLOAT8;
        v_max_radius := (v_geofence->>'radius_meters')::FLOAT8;
    ELSE
        -- Fallback default koordinat SMP THHK Tegal jika pengaturan kosong
        v_target_lat := -6.858194;
        v_target_lon := 109.137222;
        v_max_radius := 50.0;
    END IF;

    -- 4. Validasi Geofencing (PostGIS)
    v_distance := ST_DistanceSphere(
        ST_MakePoint(p_lon, p_lat),
        ST_MakePoint(v_target_lon, v_target_lat)
    );

    IF v_distance > v_max_radius THEN
        RAISE EXCEPTION 'Posisi Anda di luar area sekolah (Jarak: % meter, Batas Maks: % meter)', ROUND(v_distance::numeric), ROUND(v_max_radius::numeric);
    END IF;

    -- 5. Deteksi Keterlambatan Otomatis (WIB Timezone)
    v_now_wib := NOW() AT TIME ZONE 'Asia/Jakarta';
    IF (v_now_wib::time > '07:00:00'::time) THEN
        v_status := 'T';
    END IF;

    -- 6. Simpan log absensi
    INSERT INTO public.attendance_logs (user_id, latitude, longitude, device_id, status)
    VALUES (p_user_id, p_lat, p_lon, p_device_id, v_status);

    RETURN json_build_object(
        'status', 'success',
        'distance_meters', ROUND(v_distance::numeric, 1),
        'attendance_status', v_status
    );
END;
$$;
