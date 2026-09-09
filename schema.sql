-- dotagent schema v1
-- Branch-aware persistent memory for AI coding agents

CREATE TABLE IF NOT EXISTS branches (
  name TEXT PRIMARY KEY,
  description TEXT,
  status TEXT DEFAULT 'active',
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  branch TEXT NOT NULL,
  title TEXT NOT NULL,
  status TEXT DEFAULT 'pending',
  description TEXT,
  result TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  completed_at TEXT,
  FOREIGN KEY(branch) REFERENCES branches(name)
);

CREATE TABLE IF NOT EXISTS sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  branch TEXT NOT NULL,
  started_at TEXT DEFAULT (datetime('now')),
  summary TEXT,
  next_steps TEXT,
  model TEXT,
  FOREIGN KEY(branch) REFERENCES branches(name)
);

CREATE TABLE IF NOT EXISTS bugs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  branch TEXT,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'open',
  fix_description TEXT,
  file_path TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  fixed_at TEXT,
  FOREIGN KEY(branch) REFERENCES branches(name)
);

CREATE TABLE IF NOT EXISTS learnings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category TEXT,
  content TEXT NOT NULL,
  branch TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS decisions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  branch TEXT,
  category TEXT,
  title TEXT NOT NULL,
  context TEXT,
  decision TEXT NOT NULL,
  alternatives TEXT,
  consequences TEXT,
  status TEXT DEFAULT 'active',
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY(branch) REFERENCES branches(name)
);

CREATE TABLE IF NOT EXISTS refactorings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  branch TEXT,
  title TEXT NOT NULL,
  reason TEXT,
  scope TEXT,
  status TEXT DEFAULT 'planned',
  result TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  completed_at TEXT,
  FOREIGN KEY(branch) REFERENCES branches(name)
);

CREATE TABLE IF NOT EXISTS state (
  key TEXT PRIMARY KEY,
  value TEXT,
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS diary (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entry TEXT NOT NULL,
  workstream TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS memories (
  name TEXT PRIMARY KEY,
  type TEXT,
  description TEXT,
  content TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS rules (
  name TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO branches (name, description) VALUES ('general', 'off-branch work: questions, tooling, side tasks');
