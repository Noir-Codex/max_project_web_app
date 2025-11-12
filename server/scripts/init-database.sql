-- MAX WebApp Database Schema (idempotent version)
-- Этот скрипт создаёт недостающие таблицы, индексы и триггеры
-- Существующие объекты не затрагиваются

-- Таблица пользователей
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    telegram_id BIGINT UNIQUE,
    username VARCHAR(50),
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100),
    role VARCHAR(20) NOT NULL CHECK (role IN ('admin', 'teacher', 'student')),
    email VARCHAR(100) UNIQUE,
    password_hash VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для пользователей
CREATE INDEX IF NOT EXISTS idx_users_telegram_id ON users(telegram_id);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Таблица групп
CREATE TABLE IF NOT EXISTS groups (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    course INTEGER NOT NULL CHECK (course >= 1 AND course <= 6),
    specialty VARCHAR(200) NOT NULL,
    curator_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для групп
CREATE INDEX IF NOT EXISTS idx_groups_name ON groups(name);
CREATE INDEX IF NOT EXISTS idx_groups_course ON groups(course);
CREATE INDEX IF NOT EXISTS idx_groups_curator_id ON groups(curator_id);

-- Таблица связи студентов и групп (многие ко многим)
CREATE TABLE IF NOT EXISTS group_students (
    id SERIAL PRIMARY KEY,
    group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    student_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(group_id, student_id)
);

-- Индексы для связи групп и студентов
CREATE INDEX IF NOT EXISTS idx_group_students_group_id ON group_students(group_id);
CREATE INDEX IF NOT EXISTS idx_group_students_student_id ON group_students(student_id);

-- Таблица дисциплин
CREATE TABLE IF NOT EXISTS subjects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL UNIQUE,
    type VARCHAR(50) NOT NULL CHECK (type IN ('Лекция', 'Практика', 'Лабораторная')),
    hours INTEGER NOT NULL CHECK (hours > 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Индексы для дисциплин
CREATE INDEX IF NOT EXISTS idx_subjects_name ON subjects(name);
CREATE INDEX IF NOT EXISTS idx_subjects_type ON subjects(type);

-- Таблица расписания
CREATE TABLE IF NOT EXISTS schedule (
    id SERIAL PRIMARY KEY,
    subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
    group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    teacher_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL CHECK (day_of_week >= 1 AND day_of_week <= 7),
    time_start TIME NOT NULL,
    time_end TIME NOT NULL,
    room VARCHAR(20),
    week_type INTEGER DEFAULT 0 CHECK (week_type IN (0, 1, 2)),
    lesson_type VARCHAR(20) NOT NULL CHECK (lesson_type IN ('lecture', 'practice', 'lab')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (time_end > time_start)
);

-- Индексы для расписания
CREATE INDEX IF NOT EXISTS idx_schedule_subject_id ON schedule(subject_id);
CREATE INDEX IF NOT EXISTS idx_schedule_group_id ON schedule(group_id);
CREATE INDEX IF NOT EXISTS idx_schedule_teacher_id ON schedule(teacher_id);
CREATE INDEX IF NOT EXISTS idx_schedule_day_of_week ON schedule(day_of_week);
CREATE INDEX IF NOT EXISTS idx_schedule_week_type ON schedule(week_type);

-- Комментарий: week_type = 0 (каждую неделю), 1 (первая неделя), 2 (вторая неделя)

-- Таблица посещаемости
CREATE TABLE IF NOT EXISTS attendance (
    id SERIAL PRIMARY KEY,
    lesson_id INTEGER NOT NULL REFERENCES schedule(id) ON DELETE CASCADE,
    student_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('present', 'absent', 'late', 'excused')),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(lesson_id, student_id, date)
);

-- Индексы для посещаемости
CREATE INDEX IF NOT EXISTS idx_attendance_lesson_id ON attendance(lesson_id);
CREATE INDEX IF NOT EXISTS idx_attendance_student_id ON attendance(student_id);
CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(date);
CREATE INDEX IF NOT EXISTS idx_attendance_status ON attendance(status);

-- Функция для автоматического обновления updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Триггеры для автоматического обновления updated_at
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'update_users_updated_at'
    ) THEN
        CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'update_groups_updated_at'
    ) THEN
        CREATE TRIGGER update_groups_updated_at BEFORE UPDATE ON groups
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'update_subjects_updated_at'
    ) THEN
        CREATE TRIGGER update_subjects_updated_at BEFORE UPDATE ON subjects
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'update_schedule_updated_at'
    ) THEN
        CREATE TRIGGER update_schedule_updated_at BEFORE UPDATE ON schedule
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'update_attendance_updated_at'
    ) THEN
        CREATE TRIGGER update_attendance_updated_at BEFORE UPDATE ON attendance
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END;
$$;

-- Комментарии к таблицам
COMMENT ON TABLE users IS 'Пользователи системы (администраторы, преподаватели, студенты)';
COMMENT ON TABLE groups IS 'Учебные группы';
COMMENT ON TABLE group_students IS 'Связь студентов с группами';
COMMENT ON TABLE subjects IS 'Учебные дисциплины';
COMMENT ON TABLE schedule IS 'Расписание занятий';
COMMENT ON TABLE attendance IS 'Посещаемость студентов';

-- Вывод успешного завершения
SELECT 'Database schema created successfully!' AS status;