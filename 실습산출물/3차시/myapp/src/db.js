const path = require('path');
const Database = require('better-sqlite3');

const dbPath = path.join(__dirname, '..', 'data', 'app.db');
const db = new Database(dbPath);

db.exec(`
CREATE TABLE IF NOT EXISTS analysis (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  repo_url TEXT NOT NULL,
  owner TEXT NOT NULL,
  repo TEXT NOT NULL,
  default_branch TEXT,
  commit_sha TEXT,
  license TEXT,
  collected_at TEXT NOT NULL,
  status TEXT NOT NULL,
  error_reason TEXT
);

CREATE TABLE IF NOT EXISTS language_stat (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  analysis_id INTEGER NOT NULL REFERENCES analysis(id),
  language TEXT NOT NULL,
  bytes INTEGER NOT NULL,
  ratio REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS commit_summary (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  analysis_id INTEGER NOT NULL REFERENCES analysis(id),
  sha TEXT NOT NULL,
  message_short TEXT,
  committed_at TEXT
);

CREATE TABLE IF NOT EXISTS report (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  analysis_id INTEGER NOT NULL REFERENCES analysis(id),
  content_md TEXT NOT NULL,
  notion_page_id TEXT,
  notion_url TEXT,
  uploaded_at TEXT
);

CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  at TEXT NOT NULL,
  actor_role TEXT NOT NULL,
  action TEXT NOT NULL,
  result TEXT NOT NULL,
  detail TEXT
);
`);

function logAudit(role, action, result, detail) {
  db.prepare(
    'INSERT INTO audit_log (at, actor_role, action, result, detail) VALUES (?,?,?,?,?)'
  ).run(new Date().toISOString(), role, action, result, detail || null);
}

module.exports = { db, logAudit };
