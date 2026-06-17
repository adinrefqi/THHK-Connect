-- ==============================================================================
-- SETUP TABEL PENGAJUAN IZIN (LEAVE_REQUESTS)
-- ------------------------------------------------------------------------------
-- Tabel ini dipakai index.html (siswa mengajukan izin) dan guru_piket.html
-- (piket menyetujui/menolak), tetapi skema pembuatnya belum ada di repo.
-- File ini membuat tabel + RLS aman + indeks. Jalankan SATU KALI di SQL Editor.
--
-- Dipakai juga sebagai sumber Database Webhook "push_izin" (lihat send-push).
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.leave_requests (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID REFERENCES public.students(id) ON DELETE CASCADE,
    type           TEXT NOT NULL,                 -- 'Sakit' | 'Izin'
    reason         TEXT,
    status         TEXT NOT NULL DEFAULT 'PENDING',-- 'PENDING' | 'APPROVED' | 'REJECTED'
    attachment_url TEXT,
    created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_leave_requests_user_id ON public.leave_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_status  ON public.leave_requests(status);

-- ------------------------------------------------------------------------------
-- RLS — pola sama dengan bullying_reports (lihat setup_rls_hardening_v2.sql).
--   * INSERT  : dibuka untuk anon (siswa mengajukan izin).
--   * SELECT  : dibuka untuk anon -> dipakai siswa (riwayat) & piket (daftar).
--               Catatan: tanpa Supabase Auth, anon tidak bisa dibedakan, jadi
--               SELECT terbuka. Pengetatan butuh migrasi ke RPC sesi (sisa kerja).
--   * UPDATE  : HANYA lewat RPC bergerbang token staf (update_leave_status).
--   * DELETE  : ditolak.
-- ------------------------------------------------------------------------------
ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "leave_insert" ON public.leave_requests;
CREATE POLICY "leave_insert" ON public.leave_requests
    FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "leave_select" ON public.leave_requests;
CREATE POLICY "leave_select" ON public.leave_requests
    FOR SELECT USING (true);
-- Tanpa policy UPDATE/DELETE => ubah/hapus langsung oleh anon ditolak.

REVOKE UPDATE, DELETE  ON public.leave_requests FROM anon, authenticated;
GRANT  SELECT, INSERT  ON public.leave_requests TO   anon, authenticated;

-- ------------------------------------------------------------------------------
-- RPC: ubah status izin (approve/reject) — bergerbang token staf.
-- Mengganti pemanggilan .update() langsung di guru_piket.html.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_leave_status(
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

    UPDATE public.leave_requests
    SET status = p_status
    WHERE id = p_id;

    RETURN json_build_object('status', 'success');
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_leave_status(TEXT, UUID, TEXT) TO anon, authenticated;
