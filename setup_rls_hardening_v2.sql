-- ==============================================================================
-- PENGAMANAN RLS — PUTARAN 2 (TABEL DATA)
-- ------------------------------------------------------------------------------
-- Lanjutan dari setup_rls_hardening.sql. Menutup celah pada tabel data:
--   A. students          -> blok tulis langsung + sembunyikan kolom password
--   B. attendance_logs   -> blok tulis langsung (cegah hapus/palsu log)
--   C. bullying_reports  -> baca/ubah hanya lewat RPC bergerbang token staf
--   D. settings          -> tegaskan ulang penguncian (jaga2 bila ter-reset)
--
-- KENDALA ARSITEKTUR (penting dipahami):
--   App memakai ANON KEY untuk semua akses & TIDAK memakai Supabase Auth,
--   sehingga auth.uid() selalu NULL. RLS pada tabel yang dibaca LANGSUNG
--   tidak bisa membedakan antar-pengguna -> hanya bisa "semua boleh" atau
--   "semua ditolak". Isolasi per-pengguna sejati WAJIB lewat RPC SECURITY
--   DEFINER yang memvalidasi sesi. Lihat catatan "SISA PEKERJAAN" di SECURITY.md.
--
-- PRASYARAT: setup_rls_hardening.sql sudah dijalankan (butuh is_valid_staff_token).
--
-- CARA PAKAI: jalankan SELURUH file ini SATU KALI di Supabase > SQL Editor,
-- lalu deploy HTML terbaru (admin.html, guru_piket.html, admin_dashboard.html).
-- ==============================================================================

-- ==============================================================================
-- A. TABEL students
-- ------------------------------------------------------------------------------
-- Sebelumnya: FOR ALL USING(true) => anon bisa baca/ubah/hapus semua siswa,
-- termasuk membaca kolom `password` (plaintext) lewat select('*').
-- Sekarang:
--   * Hanya SELECT yang diizinkan dari client (dipakai dasbor admin/piket/rekap).
--   * INSERT/UPDATE/DELETE langsung DITOLAK. Semua perubahan data siswa terjadi
--     lewat RPC SECURITY DEFINER (proses_absen_siswa, reset_device_siswa) yang
--     melewati RLS.
--   * Kolom `password` dicabut hak SELECT-nya dari anon -> tak bisa dibaca,
--     bahkan dengan select('*') sekalipun (login tetap jalan via login_siswa
--     yang SECURITY DEFINER).
-- ==============================================================================
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all for students" ON public.students;

DROP POLICY IF EXISTS "students_select" ON public.students;
CREATE POLICY "students_select" ON public.students
    FOR SELECT USING (true);
-- Tidak ada policy INSERT/UPDATE/DELETE => tulis langsung oleh anon ditolak.

-- Hak kolom: cabut akses ke password, beri akses ke kolom non-sensitif.
REVOKE ALL    ON public.students FROM anon, authenticated;
GRANT  SELECT (id, nis, nama, kelas, device_id, created_at)
       ON public.students TO anon, authenticated;
-- Catatan: jangan pernah select('*') pada students dari client lagi — password
-- tidak lagi termasuk hak baca, jadi select('*') akan error. Gunakan kolom eksplisit.

-- ==============================================================================
-- B. TABEL attendance_logs
-- ------------------------------------------------------------------------------
-- Sebelumnya: FOR ALL USING(true) => anon bisa MENGHAPUS / MENGUBAH / MEMALSUKAN
-- log absensi siapa pun. Sekarang: hanya SELECT langsung (dipakai dasbor).
-- Semua INSERT terjadi lewat RPC (proses_absen_siswa / proses_absen_piket).
-- ==============================================================================
ALTER TABLE public.attendance_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all for attendance_logs" ON public.attendance_logs;

DROP POLICY IF EXISTS "attendance_select" ON public.attendance_logs;
CREATE POLICY "attendance_select" ON public.attendance_logs
    FOR SELECT USING (true);
-- Tidak ada policy tulis => INSERT/UPDATE/DELETE langsung ditolak.

REVOKE INSERT, UPDATE, DELETE ON public.attendance_logs FROM anon, authenticated;
GRANT  SELECT                 ON public.attendance_logs TO   anon, authenticated;

-- ==============================================================================
-- C. TABEL bullying_reports  (DATA SENSITIF)
-- ------------------------------------------------------------------------------
-- Sebelumnya: SELECT USING(true) => SIAPA PUN dengan anon key bisa membaca
-- seluruh aduan perundungan (nama korban, pelapor, deskripsi). UPDATE juga bebas.
-- Sekarang:
--   * INSERT tetap boleh (siswa mengirim aduan; tetap bisa anonim).
--   * SELECT & UPDATE langsung DITOLAK -> hanya lewat RPC bergerbang token staf.
-- ==============================================================================
ALTER TABLE public.bullying_reports ENABLE ROW LEVEL SECURITY;

-- Hapus policy lama yang terlalu terbuka.
DROP POLICY IF EXISTS "Allow all selects for administrators"  ON public.bullying_reports;
DROP POLICY IF EXISTS "Allow status updates for administrators" ON public.bullying_reports;
DROP POLICY IF EXISTS "Allow authenticated insert"            ON public.bullying_reports;

-- Hanya INSERT yang dibuka untuk anon (kirim aduan).
DROP POLICY IF EXISTS "bullying_insert" ON public.bullying_reports;
CREATE POLICY "bullying_insert" ON public.bullying_reports
    FOR INSERT WITH CHECK (true);
-- Tanpa policy SELECT/UPDATE => baca & ubah langsung oleh anon ditolak.

REVOKE SELECT, UPDATE, DELETE ON public.bullying_reports FROM anon, authenticated;
GRANT  INSERT                 ON public.bullying_reports TO   anon, authenticated;

-- RPC: baca daftar aduan (hanya untuk staf bertoken valid).
CREATE OR REPLACE FUNCTION public.get_bullying_reports(p_token TEXT)
RETURNS SETOF public.bullying_reports
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_valid_staff_token(p_token) THEN
        RAISE EXCEPTION 'Tidak diizinkan: sesi staf tidak valid atau kedaluwarsa.';
    END IF;

    RETURN QUERY
        SELECT * FROM public.bullying_reports
        ORDER BY created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_bullying_reports(TEXT) TO anon, authenticated;

-- RPC: ubah status aduan (hanya untuk staf bertoken valid).
CREATE OR REPLACE FUNCTION public.update_bullying_status(
    p_token  TEXT,
    p_id     UUID,
    p_status TEXT
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

    UPDATE public.bullying_reports
    SET status = p_status
    WHERE id = p_id;

    RETURN json_build_object('status', 'success');
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_bullying_status(TEXT, UUID, TEXT) TO anon, authenticated;

-- ==============================================================================
-- D. TABEL settings — tegaskan ulang penguncian (idempoten)
-- ------------------------------------------------------------------------------
-- JANGAN jalankan ulang setup_dynamic_geofence.sql: file itu melakukan
-- "DISABLE ROW LEVEL SECURITY" + "GRANT ALL ... TO anon" yang membatalkan
-- pengamanan ini. Blok di bawah memastikan settings tetap terkunci.
-- ==============================================================================
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

REVOKE ALL    ON public.settings FROM anon, authenticated;
GRANT  SELECT ON public.settings TO   anon, authenticated;

DROP POLICY IF EXISTS "settings_readable" ON public.settings;
CREATE POLICY "settings_readable" ON public.settings
    FOR SELECT USING (true);
-- Tulis hanya lewat update_geofence() (lihat setup_rls_hardening.sql).

-- ==============================================================================
-- SELESAI. Lihat SECURITY.md bagian "SISA PEKERJAAN" untuk tabel yang BELUM
-- bisa dikunci tanpa migrasi RPC / Supabase Auth:
--   - habit_logs, leave_requests, delegated_tasks (akses langsung per-pengguna)
--   - sintadu_* (tanpa RLS + password guru plaintext; dipakai app terpisah)
-- ==============================================================================
