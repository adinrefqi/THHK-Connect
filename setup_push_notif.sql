-- ==============================================================================
-- SETUP NOTIFIKASI PUSH (Firebase Cloud Messaging)
-- ------------------------------------------------------------------------------
-- Menyiapkan sisi DATABASE untuk push notification aplikasi Android (WebView).
-- Komponen:
--   1. Tabel device_tokens          -> menyimpan FCM token per perangkat/pengguna
--   2. RPC register_device_token     -> dipanggil app saat login (daftar/perbarui token)
--   3. RPC unregister_device_token   -> dipanggil app saat logout (hapus token)
--   4. Helper get_tokens_*           -> dipakai Supabase Edge Function (service_role)
--      untuk mengambil token sasaran sebelum mengirim ke FCM.
--
-- ALUR KESELURUHAN:
--   App Android  --register_device_token-->  device_tokens
--   Perubahan data (leave_requests / bullying_reports / delegated_tasks)
--        --Database Webhook-->  Edge Function "send-push"
--        --get_tokens_*-->  ambil token  --HTTP-->  FCM  --push-->  HP
--
-- PRASYARAT: tabel public.students sudah ada (insert_siswa.sql).
--
-- CARA PAKAI: jalankan SELURUH file ini SATU KALI di Supabase > SQL Editor.
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. TABEL device_tokens
-- ------------------------------------------------------------------------------
-- token       : FCM registration token (unik per instalasi app) -> PRIMARY KEY,
--               sehingga satu perangkat = satu baris (login ulang menimpa identitas).
-- user_id     : UUID siswa pemilik (NULL untuk staf admin/piket).
-- role        : 'siswa' | 'piket' | 'admin'.
-- kelas       : kelas siswa (untuk menyaring notif tugas titipan per-kelas).
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.device_tokens (
    token      TEXT PRIMARY KEY,
    user_id    UUID REFERENCES public.students(id) ON DELETE CASCADE,
    role       TEXT NOT NULL DEFAULT 'siswa',
    kelas      TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index bantu untuk query Edge Function (per role / per kelas / per user).
CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id ON public.device_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_device_tokens_role    ON public.device_tokens(role);
CREATE INDEX IF NOT EXISTS idx_device_tokens_kelas   ON public.device_tokens(kelas);

-- RLS aktif & TANPA policy => anon TIDAK bisa membaca/menulis tabel langsung.
-- Seluruh akses hanya lewat RPC SECURITY DEFINER di bawah (atau service_role
-- dari Edge Function yang otomatis mem-bypass RLS).
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.device_tokens FROM anon, authenticated;

-- ------------------------------------------------------------------------------
-- 2. RPC: daftar / perbarui token (dipanggil app via anon key saat login)
-- ------------------------------------------------------------------------------
-- Upsert berdasarkan token: jika perangkat yang sama login sebagai pengguna lain,
-- baris identitasnya diperbarui (bukan menambah baris baru).
--
-- CATATAN KEAMANAN: karena app memakai anon key tanpa Supabase Auth, fungsi ini
-- tidak bisa memverifikasi bahwa pemanggil benar-benar pemilik user_id tsb.
-- Risiko: seseorang bisa mendaftarkan token miliknya atas user_id orang lain
-- (paling parah: ikut menerima notifikasi siswa lain). Untuk konteks sekolah ini
-- diterima; bila perlu lebih ketat, rutekan lewat sesi siswa bertoken di masa depan.
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_device_token(
    p_token   TEXT,
    p_role    TEXT DEFAULT 'siswa',
    p_user_id UUID DEFAULT NULL,
    p_kelas   TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_token IS NULL OR length(trim(p_token)) = 0 THEN
        RAISE EXCEPTION 'Token FCM kosong.';
    END IF;

    INSERT INTO public.device_tokens (token, user_id, role, kelas, updated_at)
    VALUES (p_token, p_user_id, COALESCE(NULLIF(trim(p_role), ''), 'siswa'), p_kelas, NOW())
    ON CONFLICT (token) DO UPDATE
        SET user_id    = EXCLUDED.user_id,
            role       = EXCLUDED.role,
            kelas      = EXCLUDED.kelas,
            updated_at = NOW();

    RETURN json_build_object('status', 'success');
END;
$$;

GRANT EXECUTE ON FUNCTION public.register_device_token(TEXT, TEXT, UUID, TEXT) TO anon, authenticated;

-- ------------------------------------------------------------------------------
-- 3. RPC: hapus token (dipanggil app saat logout)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.unregister_device_token(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM public.device_tokens WHERE token = p_token;
    RETURN json_build_object('status', 'success');
END;
$$;

GRANT EXECUTE ON FUNCTION public.unregister_device_token(TEXT) TO anon, authenticated;

-- ==============================================================================
-- 4. HELPER UNTUK EDGE FUNCTION (pengirim push)
-- ------------------------------------------------------------------------------
-- Fungsi-fungsi ini hanya diberikan ke service_role (dipakai Edge Function
-- "send-push"). TIDAK diberikan ke anon, supaya client tidak bisa memanen
-- daftar token perangkat orang lain.
-- ==============================================================================

-- Token milik satu siswa tertentu (untuk notif status izin).
CREATE OR REPLACE FUNCTION public.get_tokens_for_user(p_user_id UUID)
RETURNS TABLE(token TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT token FROM public.device_tokens WHERE user_id = p_user_id;
$$;

-- Token semua perangkat dengan role tertentu (untuk notif aduan bullying -> 'piket').
CREATE OR REPLACE FUNCTION public.get_tokens_for_role(p_role TEXT)
RETURNS TABLE(token TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT token FROM public.device_tokens WHERE role = p_role;
$$;

-- Token semua siswa pada kelas tertentu (untuk notif tugas titipan per-kelas).
CREATE OR REPLACE FUNCTION public.get_tokens_for_kelas(p_kelas TEXT)
RETURNS TABLE(token TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT token FROM public.device_tokens WHERE kelas = p_kelas AND role = 'siswa';
$$;

-- Cabut akses helper dari anon/authenticated; hanya service_role yang boleh.
REVOKE EXECUTE ON FUNCTION public.get_tokens_for_user(UUID)  FROM anon, authenticated, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_tokens_for_role(TEXT)  FROM anon, authenticated, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_tokens_for_kelas(TEXT) FROM anon, authenticated, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_tokens_for_user(UUID)  TO service_role;
GRANT  EXECUTE ON FUNCTION public.get_tokens_for_role(TEXT)  TO service_role;
GRANT  EXECUTE ON FUNCTION public.get_tokens_for_kelas(TEXT) TO service_role;

-- ==============================================================================
-- SELESAI.
-- Langkah berikutnya (di luar SQL ini):
--   1. Buat Edge Function "send-push" yang dipicu Database Webhook pada perubahan
--      leave_requests / bullying_reports / delegated_tasks, lalu kirim ke FCM
--      memakai helper get_tokens_* di atas (pakai SERVICE_ROLE key, bukan anon).
--   2. Set Database Webhooks di Supabase Dashboard > Database > Webhooks.
-- ==============================================================================
