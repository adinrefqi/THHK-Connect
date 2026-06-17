-- ==============================================================================
-- SETUP TABEL DAN KEBIJAKAN TUGAS TITIPAN (DELEGATED TASKS)
-- ==============================================================================

-- 1. Buat Tabel delegated_tasks (Jika belum ada)
CREATE TABLE IF NOT EXISTS public.delegated_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_name TEXT NOT NULL,
    class_name TEXT NOT NULL,
    subject TEXT NOT NULL,
    task_date DATE NOT NULL DEFAULT CURRENT_DATE,
    task_description TEXT NOT NULL,
    attachment_url TEXT,
    assigned_piket TEXT,
    status TEXT DEFAULT 'Belum Disalurkan',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Mengaktifkan Row Level Security (RLS)
ALTER TABLE public.delegated_tasks ENABLE ROW LEVEL SECURITY;

-- 2. Kebijakan RLS (Policies)
-- Izinkan semua user terautentikasi/publik untuk melakukan operasi demi kemudahan single-page-app
CREATE POLICY "Allow public insert" ON public.delegated_tasks FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public select" ON public.delegated_tasks FOR SELECT USING (true);
CREATE POLICY "Allow public update" ON public.delegated_tasks FOR UPDATE USING (true);
CREATE POLICY "Allow public delete" ON public.delegated_tasks FOR DELETE USING (true);
