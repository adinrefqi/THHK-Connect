-- ==============================================================================
-- SCRIPT SETUP LENGKAP: TABEL SISWA + LOGIN RPC + DATA SISWA
-- SMP THHK - Sistem Absensi THHK Connect
-- ==============================================================================
-- Login: NIS (contoh: 08-001) | Password default: 1234
-- Urutan: Kelas 8 terlebih dahulu, lalu Kelas 9
-- ==============================================================================

-- 1. BUAT TABEL STUDENTS (Jika belum ada)
CREATE TABLE IF NOT EXISTS public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nis TEXT UNIQUE NOT NULL,
    nama TEXT NOT NULL,
    kelas TEXT NOT NULL,
    password TEXT NOT NULL DEFAULT '1234',
    device_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. BUAT TABEL ATTENDANCE LOGS (Jika belum ada)
CREATE TABLE IF NOT EXISTS public.attendance_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.students(id),
    latitude FLOAT8,
    longitude FLOAT8,
    device_id TEXT,
    status VARCHAR(1) DEFAULT 'H',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. AKTIFKAN RLS (Row Level Security)
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_logs ENABLE ROW LEVEL SECURITY;

-- Policy: RLS Hardened (Hanya SELECT yang diizinkan untuk client, tulis wajib via RPC)
DROP POLICY IF EXISTS "Allow all for students" ON public.students;
DROP POLICY IF EXISTS "students_select" ON public.students;
CREATE POLICY "students_select" ON public.students FOR SELECT USING (true);

REVOKE ALL ON public.students FROM anon, authenticated;
GRANT SELECT (id, nis, nama, kelas, device_id, created_at) ON public.students TO anon, authenticated;

DROP POLICY IF EXISTS "Allow all for attendance_logs" ON public.attendance_logs;
DROP POLICY IF EXISTS "attendance_select" ON public.attendance_logs;
CREATE POLICY "attendance_select" ON public.attendance_logs FOR SELECT USING (true);

REVOKE INSERT, UPDATE, DELETE ON public.attendance_logs FROM anon, authenticated;
GRANT SELECT ON public.attendance_logs TO anon, authenticated;

-- ==============================================================================
-- 4. INSERT DATA SISWA (Urut: Kelas 7, Kelas 8, lalu Kelas 9)
-- ==============================================================================

INSERT INTO public.students (nis, nama, kelas) VALUES
-- ==========================================
-- KELAS 7 (07-001 s/d 07-010)
-- ==========================================
('07-001', 'Aerilyn Felycia Natania Andrian', '7'),
('07-002', 'Amon Micha Wiyanto', '7'),
('07-003', 'Gabriela Princessha Christabele', '7'),
('07-004', 'Griselda Aurelia', '7'),
('07-005', 'Jadden Nathanael Kang', '7'),
('07-006', 'King Joshua Salim', '7'),
('07-007', 'Lionel Melvin', '7'),
('07-008', 'Mutiara Angelina', '7'),
('07-009', 'Sendi Kurniawan', '7'),
('07-010', 'Velove Chloe Himawan', '7'),

-- ==========================================
-- KELAS 8 (08-001 s/d 08-014)
-- ==========================================
('08-001', 'Cathleen Hava Eliora.S', '8'),
('08-002', 'Chrisna Monica Onggowarsito', '8'),
('08-003', 'Eleanore Kimberly Wong', '8'),
('08-004', 'Engracia Sarah Chrisyabelle.S', '8'),
('08-005', 'Jasson Alvaro Gunarto', '8'),
('08-006', 'Jennifer Aurelia Febriana', '8'),
('08-007', 'Keane William Gunawan', '8'),
('08-008', 'Kenichi Alvaro Gavriel', '8'),
('08-009', 'Keyzia El Ryansyah', '8'),
('08-010', 'Melvin Antan Djaya', '8'),
('08-011', 'M. Akhil Fadillah', '8'),
('08-012', 'Nathasya Michelle Lee', '8'),
('08-013', 'Nicholas Willson Kasuya', '8'),
('08-014', 'Vincentius Fernandez Suharto', '8'),

-- ==========================================
-- KELAS 9 (09-001 s/d 09-027)
-- ==========================================
('09-001', 'Calvin Fransisco', '9'),
('09-002', 'Celine Octavia Kusuma', '9'),
('09-003', 'Clarice Siera Elisabeth Rahardjo', '9'),
('09-004', 'Clement Raphael Kurnia', '9'),
('09-005', 'Darwin Adelio Alvaro', '9'),
('09-006', 'Erland Adriano Budiman', '9'),
('09-007', 'Faris Mahardika Luki', '9'),
('09-008', 'Flourencia Alvina', '9'),
('09-009', 'Giovanni Agnell Tanuwijaya', '9'),
('09-010', 'Gisella Cellena Cleola Andrian', '9'),
('09-011', 'Graciana Shinta Dewi', '9'),
('09-012', 'Henedictus Greffy Jeisen Putra', '9'),
('09-013', 'Ivana Jacinda', '9'),
('09-014', 'Jefferson Setiawan', '9'),
('09-015', 'Jesslyn Anna Belle Arminta Prawiro', '9'),
('09-016', 'Jesslyn Yoewono', '9'),
('09-017', 'Jocelyn Octavia Gunawan', '9'),
('09-018', 'Johan Faizal', '9'),
('09-019', 'Keiko Lee Yohanes', '9'),
('09-020', 'Marquez Loris', '9'),
('09-021', 'Michelle Angelica Setiono', '9'),
('09-022', 'Mikhaela Josephine Soetjipto', '9'),
('09-023', 'Octavelie Sila Kirana', '9'),
('09-024', 'Reynaldo Xavier Alexander Gunawan', '9'),
('09-025', 'Sebastian Moses Firlandi', '9'),
('09-026', 'Yuriko Jessi Setiawan', '9'),
('09-027', 'Desiani Natalia Siallagan', '9')
ON CONFLICT (nis) DO UPDATE SET
    nama = EXCLUDED.nama,
    kelas = EXCLUDED.kelas;

-- ==============================================================================
-- 5. FUNGSI RPC: LOGIN SISWA (Sederhana, tanpa auth.users)
-- ==============================================================================
DROP FUNCTION IF EXISTS login_siswa(TEXT, TEXT);

CREATE OR REPLACE FUNCTION login_siswa(p_nis TEXT, p_password TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student RECORD;
BEGIN
    SELECT id, nis, nama, kelas
    INTO v_student
    FROM public.students
    WHERE nis = p_nis AND password = p_password;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NIS atau password salah';
    END IF;

    RETURN json_build_object(
        'id', v_student.id,
        'nis', v_student.nis,
        'nama', v_student.nama,
        'kelas', v_student.kelas
    );
END;
$$;

-- ==============================================================================
-- 6. FUNGSI RPC: PROSES ABSEN SISWA (Geofencing + Device Binding)
-- ==============================================================================
CREATE EXTENSION IF NOT EXISTS postgis;

DROP FUNCTION IF EXISTS public.proses_absen_siswa(UUID, FLOAT8, FLOAT8, TEXT);

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
BEGIN
    -- 1. Ambil data siswa
    SELECT id, device_id INTO v_student FROM public.students WHERE id = p_user_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Siswa tidak ditemukan dalam database';
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
DROP FUNCTION IF EXISTS public.proses_absen_piket(UUID, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.proses_absen_piket(
    p_student_id UUID,
    p_teacher_note TEXT,
    p_status TEXT,
    p_token TEXT
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

-- RPC reset_device_siswa
DROP FUNCTION IF EXISTS public.reset_device_siswa(UUID);
DROP FUNCTION IF EXISTS public.reset_device_siswa(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.reset_device_siswa(
    p_student_id UUID,
    p_token TEXT
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
