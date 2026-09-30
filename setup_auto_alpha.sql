-- ==============================================================================
-- ALPHA OTOMATIS PUKUL 15:00 WIB
-- ------------------------------------------------------------------------------
-- Setiap Senin–Jumat pukul 15:00 WIB, siswa kelas 7/8/9 yang belum punya catatan
-- absen apa pun hari itu dicatat 'A' (device_id = 'OTOMATIS 15:00').
--
-- Pengaman:
--   - Sabtu & Minggu dilewati.
--   - Hari libur dilewati: jika hari itu TIDAK ADA satu pun siswa yang absen,
--     sekolah dianggap libur dan tidak ada yang ditandai Alpha.
--     (ponytail: tebakan dari data, bukan kalender. Jika kelak ada hari sekolah
--     tanpa absen sama sekali atau libur per-kelas, tambahkan tabel hari_libur.)
--   - Fungsi TIDAK bisa dipanggil dari aplikasi (anon) — hanya oleh pg_cron.
--
-- Siswa yang sudah ditandai A masih bisa dikoreksi guru piket (tombol H/T/S/I
-- di kartu siswa, lewat proses_absen_piket yang meng-UPDATE log hari itu).
--
-- CARA PAKAI: jalankan SELURUH file ini di Supabase > SQL Editor. Aman
-- dijalankan ulang (jadwal dengan nama yang sama akan diperbarui).
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE OR REPLACE FUNCTION public.auto_alpha_harian()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_today DATE        := (NOW() AT TIME ZONE 'Asia/Jakarta')::DATE;
    v_start TIMESTAMPTZ := v_today::TIMESTAMP AT TIME ZONE 'Asia/Jakarta';
    v_end   TIMESTAMPTZ := v_start + INTERVAL '1 day';
    v_count INTEGER;
BEGIN
    -- Sabtu (6) & Minggu (7)
    IF EXTRACT(ISODOW FROM v_today) > 5 THEN
        RETURN 0;
    END IF;

    -- Hari libur: tidak ada satu pun absen hari ini
    IF NOT EXISTS (
        SELECT 1 FROM public.attendance_logs
        WHERE created_at >= v_start AND created_at < v_end
    ) THEN
        RETURN 0;
    END IF;

    INSERT INTO public.attendance_logs (user_id, latitude, longitude, device_id, status)
    SELECT s.id, NULL, NULL, 'OTOMATIS 15:00', 'A'
    FROM public.students s
    WHERE s.kelas IN ('7', '8', '9')
      AND NOT EXISTS (
          SELECT 1 FROM public.attendance_logs l
          WHERE l.user_id = s.id
            AND l.created_at >= v_start AND l.created_at < v_end
      );

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- Supabase memberi EXECUTE ke anon secara default: cabut, supaya tidak ada yang
-- bisa memicu Alpha massal lebih awal dari aplikasi.
REVOKE ALL ON FUNCTION public.auto_alpha_harian() FROM PUBLIC, anon, authenticated;

-- pg_cron memakai UTC: 08:00 UTC = 15:00 WIB. Hari 1-5 = Senin–Jumat.
SELECT cron.schedule(
    'auto-alpha-harian',
    '0 8 * * 1-5',
    $$SELECT public.auto_alpha_harian();$$
);

-- ------------------------------------------------------------------------------
-- CEK (opsional, tidak mengubah data):
--   Jadwal terdaftar : SELECT jobname, schedule, active FROM cron.job;
--   Riwayat jalan    : SELECT status, return_message, start_time
--                      FROM cron.job_run_details ORDER BY start_time DESC LIMIT 5;
--   Pratinjau hari ini (siapa yang AKAN ditandai A jika jam 15:00 sekarang):
--     SELECT s.kelas, s.nis, s.nama FROM public.students s
--     WHERE s.kelas IN ('7','8','9') AND NOT EXISTS (
--       SELECT 1 FROM public.attendance_logs l WHERE l.user_id = s.id
--         AND l.created_at >= ((NOW() AT TIME ZONE 'Asia/Jakarta')::DATE::TIMESTAMP AT TIME ZONE 'Asia/Jakarta'))
--     ORDER BY s.kelas, s.nama;
-- Mematikan: SELECT cron.unschedule('auto-alpha-harian');
-- ------------------------------------------------------------------------------
