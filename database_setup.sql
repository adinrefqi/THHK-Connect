-- ==============================================================================
-- SETUP TABEL DATABASE
-- ==============================================================================

-- 1. Buat Tabel students (Jika belum ada)
-- Tabel ini terhubung langsung dengan sistem Autentikasi bawaan Supabase (auth.users)
CREATE TABLE IF NOT EXISTS public.students (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    nama_lengkap TEXT,
    device_id TEXT
);

-- 2. Buat Tabel attendance_logs (Jika belum ada)
CREATE TABLE IF NOT EXISTS public.attendance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
    latitude FLOAT8,
    longitude FLOAT8,
    device_id TEXT,
    status VARCHAR(1) DEFAULT 'H',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- SETUP EXTENSION & INDEX
-- ==============================================================================

-- Mengaktifkan ekstensi PostGIS (Wajib untuk kalkulasi jarak)
CREATE EXTENSION IF NOT EXISTS postgis;

-- Tambahkan Index pada device_id agar proses query pencarian device lebih cepat
CREATE INDEX IF NOT EXISTS idx_students_device_id ON public.students(device_id);

-- ==============================================================================
-- FUNGSI UTAMA (RPC)
-- ==============================================================================

-- Buat fungsi RPC proses_absen_siswa
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
    v_target_lat FLOAT8 := -6.858194;
    v_target_lon FLOAT8 := 109.137222;
    v_max_radius FLOAT8 := 50.0;
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

    -- 3. Validasi Geofencing (PostGIS)
    v_distance := ST_DistanceSphere(
        ST_MakePoint(p_lon, p_lat),
        ST_MakePoint(v_target_lon, v_target_lat)
    );

    IF v_distance > v_max_radius THEN
        RAISE EXCEPTION 'Posisi Anda di luar area sekolah (Jarak: % meter)', ROUND(v_distance::numeric);
    END IF;

    -- 4. Deteksi Keterlambatan Otomatis (WIB Timezone)
    v_now_wib := NOW() AT TIME ZONE 'Asia/Jakarta';
    IF (v_now_wib::time > '07:00:00'::time) THEN
        v_status := 'T';
    END IF;

    -- 5. Simpan log absensi
    INSERT INTO public.attendance_logs (user_id, latitude, longitude, device_id, status)
    VALUES (p_user_id, p_lat, p_lon, p_device_id, v_status);

    RETURN json_build_object(
        'status', 'success',
        'distance_meters', ROUND(v_distance::numeric, 1),
        'attendance_status', v_status
    );
END;
$$;

-- Alias proses_absen_siswa_v3
DROP FUNCTION IF EXISTS public.proses_absen_siswa_v3(UUID, FLOAT8, FLOAT8, TEXT);
CREATE OR REPLACE FUNCTION public.proses_absen_siswa_v3(
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
    v_res JSON;
BEGIN
    v_res := public.proses_absen_siswa(p_user_id, p_lat, p_lon, p_device_id);
    RETURN v_res;
END;
$$;

-- RPC proses_absen_piket
DROP FUNCTION IF EXISTS public.proses_absen_piket(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.proses_absen_piket(
    p_student_id UUID,
    p_teacher_note TEXT,
    p_status TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.attendance_logs (user_id, latitude, longitude, device_id, status)
    VALUES (p_student_id, NULL, NULL, p_teacher_note, p_status);

    RETURN json_build_object('status', 'success');
END;
$$;

-- RPC reset_device_siswa
DROP FUNCTION IF EXISTS public.reset_device_siswa(UUID);
CREATE OR REPLACE FUNCTION public.reset_device_siswa(
    p_student_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.students
    SET device_id = NULL
    WHERE id = p_student_id;

    RETURN json_build_object('status', 'success');
END;
$$;
