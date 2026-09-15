-- ==============================================================================
-- FIX: ABSEN DOBEL DARI PIKET / PERSETUJUAN IZIN
-- ------------------------------------------------------------------------------
-- proses_absen_piket dulu selalu INSERT baris baru, sehingga siswa bisa punya
-- 2+ log di hari yang sama (mis. absen H lalu izin disetujui, atau dua piket
-- menekan tombol bersamaan). Versi ini: jika siswa sudah punya log hari ini
-- (WIB), log terakhirnya DIPERBARUI; jika belum, baru INSERT.
--
-- Jalankan SATU KALI di Supabase SQL Editor. Aman dijalankan ulang.
-- Menggantikan definisi di setup_rls_hardening.sql & insert_siswa.sql —
-- JANGAN jalankan ulang kedua file itu setelah file ini.
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.proses_absen_piket(
    p_student_id   UUID,
    p_teacher_note TEXT,
    p_status       TEXT,
    p_token        TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_today_start TIMESTAMPTZ := ((NOW() AT TIME ZONE 'Asia/Jakarta')::date)::timestamp AT TIME ZONE 'Asia/Jakarta';
    v_log_id      UUID;
BEGIN
    IF NOT public.is_valid_staff_token(p_token) THEN
        RAISE EXCEPTION 'Tidak diizinkan: sesi staf tidak valid atau kedaluwarsa.';
    END IF;

    -- Kunci per siswa agar dua klik bersamaan tidak sama-sama INSERT
    PERFORM pg_advisory_xact_lock(hashtext(p_student_id::text));

    SELECT id INTO v_log_id
    FROM public.attendance_logs
    WHERE user_id = p_student_id
      AND created_at >= v_today_start
      AND created_at <  v_today_start + INTERVAL '1 day'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_log_id IS NULL THEN
        INSERT INTO public.attendance_logs (user_id, latitude, longitude, device_id, status)
        VALUES (p_student_id, NULL, NULL, p_teacher_note, p_status);
    ELSE
        UPDATE public.attendance_logs
        SET status = p_status, device_id = p_teacher_note
        WHERE id = v_log_id;
    END IF;

    RETURN json_build_object('status', 'success', 'updated', v_log_id IS NOT NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.proses_absen_piket(UUID, TEXT, TEXT, TEXT) TO anon, authenticated;
