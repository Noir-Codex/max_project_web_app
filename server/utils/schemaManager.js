const { query } = require('../config/database');

async function tableExists(tableName) {
  const result = await query('SELECT to_regclass($1) AS regclass', [tableName]);
  return Boolean(result.rows[0]?.regclass);
}

async function ensureTable(tableName, createSql) {
  const exists = await tableExists(tableName);

  if (!exists) {
    console.log(`🛠️  Создаю таблицу ${tableName}...`);
    await query(createSql);
    console.log(`✅ Таблица ${tableName} создана`);
  } else {
    console.log(`ℹ️  Таблица ${tableName} уже существует`);
  }
}

async function ensureUsersTable() {
  await ensureTable(
    'public.users',
    `
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
  `
  );

  await query('CREATE INDEX IF NOT EXISTS idx_users_telegram_id ON users(telegram_id)');
  await query('CREATE INDEX IF NOT EXISTS idx_users_role ON users(role)');
  await query('CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)');
}

async function ensureGroupsTable() {
  await ensureTable(
    'public.groups',
    `
    CREATE TABLE IF NOT EXISTS groups (
      id SERIAL PRIMARY KEY,
      name VARCHAR(50) NOT NULL UNIQUE,
      course INTEGER NOT NULL CHECK (course >= 1 AND course <= 6),
      specialty VARCHAR(200) NOT NULL,
      curator_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `
  );

  await query('CREATE INDEX IF NOT EXISTS idx_groups_name ON groups(name)');
  await query('CREATE INDEX IF NOT EXISTS idx_groups_course ON groups(course)');
  await query('CREATE INDEX IF NOT EXISTS idx_groups_curator_id ON groups(curator_id)');
}

async function ensureSubjectsTable() {
  await ensureTable(
    'public.subjects',
    `
    CREATE TABLE IF NOT EXISTS subjects (
      id SERIAL PRIMARY KEY,
      name VARCHAR(200) NOT NULL UNIQUE,
      type VARCHAR(50) NOT NULL CHECK (type IN ('Лекция', 'Практика', 'Лабораторная')),
      hours INTEGER NOT NULL CHECK (hours > 0),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `
  );

  await query('CREATE INDEX IF NOT EXISTS idx_subjects_name ON subjects(name)');
  await query('CREATE INDEX IF NOT EXISTS idx_subjects_type ON subjects(type)');
}

async function ensureScheduleTable() {
  await ensureTable(
    'public.schedule',
    `
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
  `
  );

  await query('CREATE INDEX IF NOT EXISTS idx_schedule_subject_id ON schedule(subject_id)');
  await query('CREATE INDEX IF NOT EXISTS idx_schedule_group_id ON schedule(group_id)');
  await query('CREATE INDEX IF NOT EXISTS idx_schedule_teacher_id ON schedule(teacher_id)');
  await query('CREATE INDEX IF NOT EXISTS idx_schedule_day_of_week ON schedule(day_of_week)');
  await query('CREATE INDEX IF NOT EXISTS idx_schedule_week_type ON schedule(week_type)');
}

async function ensureGroupStudentsTable() {
  await ensureTable(
    'public.group_students',
    `
    CREATE TABLE IF NOT EXISTS group_students (
      id SERIAL PRIMARY KEY,
      group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      student_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(group_id, student_id)
    );
  `
  );

  await query('CREATE INDEX IF NOT EXISTS idx_group_students_group_id ON group_students(group_id)');
  await query('CREATE INDEX IF NOT EXISTS idx_group_students_student_id ON group_students(student_id)');
}

async function ensureAttendanceTable() {
  await ensureTable(
    'public.attendance',
    `
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
  `
  );

  await query('CREATE INDEX IF NOT EXISTS idx_attendance_lesson_id ON attendance(lesson_id)');
  await query('CREATE INDEX IF NOT EXISTS idx_attendance_student_id ON attendance(student_id)');
  await query('CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(date)');
  await query('CREATE INDEX IF NOT EXISTS idx_attendance_status ON attendance(status)');
}

async function ensureUpdateTrigger() {
  await query(`
    CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
    BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
    END;
    $$ language 'plpgsql';
  `);

  const triggerStatements = [
    {
      name: 'update_users_updated_at',
      table: 'users'
    },
    {
      name: 'update_groups_updated_at',
      table: 'groups'
    },
    {
      name: 'update_subjects_updated_at',
      table: 'subjects'
    },
    {
      name: 'update_schedule_updated_at',
      table: 'schedule'
    },
    {
      name: 'update_attendance_updated_at',
      table: 'attendance'
    }
  ];

  for (const { name, table } of triggerStatements) {
    await query(`
      DO $$
      BEGIN
          IF NOT EXISTS (
              SELECT 1 FROM pg_trigger WHERE tgname = '${name}'
          ) THEN
              EXECUTE 'CREATE TRIGGER ${name} BEFORE UPDATE ON ${table}
                       FOR EACH ROW EXECUTE FUNCTION update_updated_at_column()';
          END IF;
      END;
      $$;
    `);
  }
}

async function ensureDatabaseSchema() {
  console.log('🔍 Проверка схемы базы данных...');

  await ensureUsersTable();
  await ensureGroupsTable();
  await ensureSubjectsTable();
  await ensureScheduleTable();
  await ensureGroupStudentsTable();
  await ensureAttendanceTable();
  await ensureUpdateTrigger();

  console.log('✅ Проверка схемы базы данных завершена');
}

module.exports = {
  ensureDatabaseSchema
};

