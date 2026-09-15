-- ==============================================================================
-- FIX: ABSEN DOBEL DARI PIKET + IZIN DICATAT DI TANGGAL PENGAJUAN
-- ------------------------------------------------------------------------------
-- 1. proses_absen_piket dulu selalu INSERT baris baru, sehingga siswa bisa punya
--    2+ log di hari yang sama. Versi ini: jika siswa sudah punya log di hari
--    tersebut (WIB), log terakhirnya DIPERBARUI; jika belum, baru INSERT.
-- 2. Parameter opsional p_tanggal (DATE): izin yang disetujui terlambat dicatat
--    di tanggal pengajuan, bukan tanggal persetujuan. Tanpa p_tanggal = hari ini.
--
-- Jalankan di Supabase SQL Editor. Aman dijalankan ulang.
-- Menggantikan definisi di setup_rls_hardening.sql & insert_siswa.sql —
-- JANGAN jalankan ulang kedua file itu setelah file ini.
-- ==============================================================================

-- Hapus versi 4 parameter agar tidak bentrok (ambigu) dengan versi 5 parameter
DROP FUNCTION IF EXISTS public.proses_absen_piket(UUID, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.proses_absen_piket(
    p_student_id   UUID,
    p_teacher_note TEXT,
    p_status       TEXT,
    p_token        TEXT,
    p_tanggal      DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_today     DATE        := (NOW() AT TIME ZONE 'Asia/Jakarta')::date;
    v_day       DATE        := COALESCE(p_tanggal, v_today);
    v_day_start TIMESTAMPTZ := v_day::timestamp AT TIME ZONE 'Asia/Jakarta';
    v_log_id    UUID;
BEGIN
    IF NOT public.is_valid_staff_token(p_token) THEN
        RAISE EXCEPTION 'Tidak diizinkan: sesi staf tidak valid atau kedaluwarsa.';
    END IF;

    IF v_day > v_today THEN
        RAISE EXCEPTION 'Tanggal absen tidak boleh di masa depan.';
    END IF;

    -- Kunci per siswa agar dua klik bersamaan tidak sama-sama INSERT
    PERFORM pg_advisory_xact_lock(hashtext(p_student_id::text));

    SELECT id INTO v_log_id
    FROM public.attendance_logs
    WHERE user_id = p_student_id
      AND created_at >= v_day_start
      AND created_at <  v_day_start + INTERVAL '1 day'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_log_id IS NULL THEN
        INSERT INTO public.attendance_logs (user_id, latitude, longitude, device_id, status, created_at)
        VALUES (
            p_student_id, NULL, NULL, p_teacher_note, p_status,
            -- Hari ini: jam sekarang. Tanggal lampau: 07:00 WIB di tanggal itu.
            CASE WHEN v_day = v_today THEN NOW() ELSE v_day_start + INTERVAL '7 hours' END
        );
    ELSE
        UPDATE public.attendance_logs
        SET status = p_status, device_id = p_teacher_note
        WHERE id = v_log_id;
    END IF;

    RETURN json_build_object('status', 'success', 'updated', v_log_id IS NOT NULL, 'tanggal', v_day);
END;
$$;

GRANT EXECUTE ON FUNCTION public.proses_absen_piket(UUID, TEXT, TEXT, TEXT, DATE) TO anon, authenticated;
