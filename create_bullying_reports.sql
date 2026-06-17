-- ==============================================================================
-- SETUP TABEL DAN KEBIJAKAN LAPORAN BULLYING
-- ==============================================================================

-- 1. Buat Tabel bullying_reports (Jika belum ada)
CREATE TABLE IF NOT EXISTS public.bullying_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
    reporter_name_display TEXT NOT NULL,
    victim_name TEXT NOT NULL,
    bullying_type VARCHAR(50) NOT NULL,
    incident_location TEXT NOT NULL,
    description TEXT NOT NULL,
    attachment_url TEXT,
    status VARCHAR(20) DEFAULT 'PENDING',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security (RLS) pada tabel
ALTER TABLE public.bullying_reports ENABLE ROW LEVEL SECURITY;

-- 2. Kebijakan RLS (Policies)

-- Izinkan semua user terautentikasi (anonim key) untuk mengirimkan laporan (INSERT)
CREATE POLICY "Allow authenticated insert" 
ON public.bullying_reports 
FOR INSERT 
WITH CHECK (true);

-- Izinkan guru/admin untuk membaca semua laporan (SELECT)
CREATE POLICY "Allow all selects for administrators" 
ON public.bullying_reports 
FOR SELECT 
USING (true); -- Kunci kebenaran logika ini diatur di sisi client, atau dapat disempurnakan berdasarkan peran

-- Izinkan guru/admin untuk memperbarui status laporan (UPDATE)
CREATE POLICY "Allow status updates for administrators" 
ON public.bullying_reports 
FOR UPDATE 
USING (true);
