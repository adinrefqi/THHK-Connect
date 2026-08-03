-- =================================================================================
-- SCRIPT SETUP DATABASE SUPABASE - SINTADU GURU (JURNAL & NILAI)
-- =================================================================================
-- Silakan copy dan jalankan (RUN) kode ini di menu "SQL Editor" pada Supabase Anda.
-- =================================================================================

-- 1. TABEL GURU (TEACHERS)
-- Menyimpan kredensial dan daftar mata pelajaran yang diampu
CREATE TABLE IF NOT EXISTS sintadu_teachers (
    username TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    password TEXT NOT NULL, -- Anda bisa menggunakan hashing nanti, untuk sekarang diset teks biasa
    subjects TEXT[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 2. TABEL SISWA (STUDENTS)
-- Menyimpan data identitas siswa berdasarkan NIS
CREATE TABLE IF NOT EXISTS sintadu_students (
    nis TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    class_name TEXT NOT NULL, -- 'Kelas 7', 'Kelas 8', 'Kelas 9'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 3. TABEL JURNAL MENGAJAR (JOURNALS)
-- Menyimpan log aktivitas mengajar harian setiap guru
CREATE TABLE IF NOT EXISTS sintadu_journals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_username TEXT REFERENCES sintadu_teachers(username) ON DELETE CASCADE,
    date DATE NOT NULL,
    class_name TEXT NOT NULL,
    subject TEXT NOT NULL,
    topic TEXT NOT NULL,
    method TEXT NOT NULL,
    sakit INTEGER DEFAULT 0,
    izin INTEGER DEFAULT 0,
    alpha INTEGER DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now())
);

-- 4. TABEL NILAI SISWA (GRADES)
-- Menggunakan format normalized: 1 baris untuk 1 nilai (Tugas 1, UH 1, UTS, dst)
CREATE TABLE IF NOT EXISTS sintadu_grades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_nis TEXT REFERENCES sintadu_students(nis) ON DELETE CASCADE,
    teacher_username TEXT REFERENCES sintadu_teachers(username) ON DELETE SET NULL,
    subject TEXT NOT NULL,
    category TEXT NOT NULL, -- Kategori: 'Tugas', 'UH', 'UTS', 'UAS'
    task_name TEXT NOT NULL, -- Nama spesifik: 'Tugas 1', 'Tugas Aljabar', 'UTS'
    score NUMERIC NOT NULL CHECK (score >= 0 AND score <= 100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
    -- Memastikan tidak ada duplikasi input nilai untuk tugas yang sama pada siswa yang sama
    UNIQUE(student_nis, subject, category, task_name)
);

-- =================================================================================
-- INDEKS UNTUK PERFORMA (MEMPERCEPAT PENCARIAN)
-- =================================================================================
CREATE INDEX IF NOT EXISTS idx_journals_teacher ON sintadu_journals(teacher_username);
CREATE INDEX IF NOT EXISTS idx_journals_date ON sintadu_journals(date);
CREATE INDEX IF NOT EXISTS idx_grades_student ON sintadu_grades(student_nis);
CREATE INDEX IF NOT EXISTS idx_grades_subject ON sintadu_grades(subject);

-- =================================================================================
-- (OPSIONAL) DUMMY DATA INISIALISASI GURU
-- Jika Anda ingin langsung memasukkan beberapa contoh guru dari data sebelumnya, 
-- hilangkan tanda komentar (--) di bawah ini:
-- =================================================================================

INSERT INTO sintadu_teachers (username, name, password, subjects) VALUES
('wahyu', 'Sri Wahyuningsih, S.s., S.Pd.', 'admin54321', '{}'),
('yanuar', 'Yanuar Evanto, S.Pd', 'guru123', '{"IPA", "TIK"}'),
('thevea', 'Thevea Yurike R., S.Pd.', 'guru123', '{"Matematika"}'),
('elsa', 'Elsa Anggraeni, S.T.', 'guru123', '{"Bahasa Mandarin"}')
ON CONFLICT (username) DO NOTHING;
