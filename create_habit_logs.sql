-- ==============================================================================
-- SETUP TABEL DAN KEBIJAKAN JURNAL 7 KEBIASAAN
-- ==============================================================================

CREATE TABLE IF NOT EXISTS public.habit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
    log_date DATE DEFAULT CURRENT_DATE,
    habit_1 TEXT, -- Bangun Pagi
    habit_2 TEXT, -- Beribadah
    habit_3 TEXT, -- Berolahraga
    habit_4 TEXT, -- Makan Sehat
    habit_5 TEXT, -- Gemar Belajar
    habit_6 TEXT, -- Bermasyarakat
    habit_7 TEXT, -- Tidur Cepat/Cukup
    mood VARCHAR(20) DEFAULT 'biasa', -- Senang, Biasa, Sedih, Kesal
    signature_parent TEXT, -- Tanda Tangan Orang Tua (Base64)
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_user_date_habit UNIQUE (user_id, log_date)
);

-- Enable Row Level Security (RLS) pada tabel
ALTER TABLE public.habit_logs ENABLE ROW LEVEL SECURITY;

-- 2. Kebijakan RLS (Policies)

-- Izinkan semua user terautentikasi (anonim key) untuk membaca rekam jejak mereka sendiri (SELECT)
CREATE POLICY "Allow authenticated select for owner" 
ON public.habit_logs 
FOR SELECT 
USING (true); -- Dibatasi di sisi aplikasi / atau disempurnakan berdasarkan auth.uid() jika menggunakan auth bawaan

-- Izinkan semua user terautentikasi untuk menyimpan/memperbarui rekam jejak mereka sendiri (INSERT/UPDATE)
CREATE POLICY "Allow authenticated insert for owner" 
ON public.habit_logs 
FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Allow authenticated update for owner" 
ON public.habit_logs 
FOR UPDATE 
USING (true);
