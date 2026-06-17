-- ==============================================================================
-- SETUP STRUKTUR DATA BARU UNTUK KELAS BIMBINGAN KONSELING (BK)
-- ==============================================================================

-- Tambahkan kolom counselor_notes (catatan bimbingan konseling) ke tabel bullying_reports jika belum ada
ALTER TABLE public.bullying_reports ADD COLUMN IF NOT EXISTS counselor_notes TEXT;
