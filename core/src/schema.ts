import type Database from "better-sqlite3";

export const SCHEMA_VERSION = 2;

export const SCHEMA_SQL = `
-- Nodes: the universal record
CREATE TABLE IF NOT EXISTS things (
  id TEXT PRIMARY KEY,
  content TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT,
  created_by TEXT DEFAULT 'user',
  status TEXT DEFAULT 'active' CHECK(status IN ('active', 'archived', 'deleted'))
);

-- Node types: Tana-style supertags with field schemas
CREATE TABLE IF NOT EXISTS tags (
  name TEXT PRIMARY KEY,
  display_name TEXT DEFAULT '',
  description TEXT DEFAULT '',
  schema_json TEXT DEFAULT '[]',
  icon TEXT DEFAULT '',
  color TEXT DEFAULT '',
  published_by TEXT DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT
);

-- Typing: "this thing IS a note" (with typed field values)
CREATE TABLE IF NOT EXISTS thing_tags (
  thing_id TEXT NOT NULL REFERENCES things(id) ON DELETE CASCADE,
  tag_name TEXT NOT NULL REFERENCES tags(name),
  field_values_json TEXT DEFAULT '{}',
  tagged_at TEXT NOT NULL,
  PRIMARY KEY (thing_id, tag_name)
);

-- Relationships: "this note MENTIONS that person"
CREATE TABLE IF NOT EXISTS edges (
  source_id TEXT NOT NULL REFERENCES things(id) ON DELETE CASCADE,
  target_id TEXT NOT NULL REFERENCES things(id) ON DELETE CASCADE,
  relationship TEXT NOT NULL,
  properties_json TEXT DEFAULT '{}',
  created_by TEXT DEFAULT 'user',
  created_at TEXT NOT NULL,
  UNIQUE(source_id, target_id, relationship)
);

-- MCP tool definitions: named graph operations
CREATE TABLE IF NOT EXISTS tools (
  name TEXT PRIMARY KEY,
  display_name TEXT DEFAULT '',
  description TEXT DEFAULT '',
  tool_type TEXT DEFAULT 'query' CHECK(tool_type IN ('query', 'mutation')),
  input_schema_json TEXT DEFAULT '{}',
  definition_json TEXT DEFAULT '{}',
  published_by TEXT DEFAULT '',
  enabled TEXT DEFAULT 'true',
  created_at TEXT NOT NULL,
  updated_at TEXT
);

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);

-- Full-text search on thing content
CREATE VIRTUAL TABLE IF NOT EXISTS things_fts USING fts5(
  content,
  content='things',
  content_rowid='rowid'
);

-- FTS triggers: keep the index in sync with things table
CREATE TRIGGER IF NOT EXISTS things_fts_insert AFTER INSERT ON things BEGIN
  INSERT INTO things_fts(rowid, content) VALUES (new.rowid, new.content);
END;

CREATE TRIGGER IF NOT EXISTS things_fts_delete AFTER DELETE ON things BEGIN
  INSERT INTO things_fts(things_fts, rowid, content) VALUES('delete', old.rowid, old.content);
END;

CREATE TRIGGER IF NOT EXISTS things_fts_update AFTER UPDATE OF content ON things BEGIN
  INSERT INTO things_fts(things_fts, rowid, content) VALUES('delete', old.rowid, old.content);
  INSERT INTO things_fts(rowid, content) VALUES (new.rowid, new.content);
END;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_things_status ON things(status);
CREATE INDEX IF NOT EXISTS idx_things_created ON things(created_at);
CREATE INDEX IF NOT EXISTS idx_things_created_by ON things(created_by);
CREATE INDEX IF NOT EXISTS idx_thing_tags_tag ON thing_tags(tag_name);
CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id);
CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id);
CREATE INDEX IF NOT EXISTS idx_edges_rel ON edges(relationship);
`;

/**
 * Initialize database schema. Idempotent — safe to call on every startup.
 */
export function initSchema(db: Database.Database): void {
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.exec(SCHEMA_SQL);

  // Run migrations
  migrateToV2(db);

  // Record schema version
  db.prepare("INSERT OR REPLACE INTO schema_version (version, applied_at) VALUES (?, ?)").run(
    SCHEMA_VERSION,
    new Date().toISOString(),
  );
}

/**
 * V2 migration: rename daily-note → note, remove person/project builtins,
 * rename tools (read-daily-notes → read-notes, read-recent-notes → read-recent).
 */
function migrateToV2(db: Database.Database): void {
  const applied = db.prepare("SELECT version FROM schema_version WHERE version = 2").get();
  if (applied) return;

  // Rename tag: daily-note → note
  const hasOld = db.prepare("SELECT name FROM tags WHERE name = 'daily-note'").get();
  const hasNew = db.prepare("SELECT name FROM tags WHERE name = 'note'").get();
  if (hasOld && !hasNew) {
    db.prepare("INSERT INTO tags (name, display_name, description, schema_json, icon, color, published_by, created_at) SELECT 'note', 'Note', description, schema_json, icon, color, published_by, created_at FROM tags WHERE name = 'daily-note'").run();
    db.prepare("UPDATE thing_tags SET tag_name = 'note' WHERE tag_name = 'daily-note'").run();
    db.prepare("DELETE FROM tags WHERE name = 'daily-note'").run();
  }

  // Remove person/project builtins (only if published by parachute-daily and unused)
  for (const tag of ["person", "project"]) {
    const usage = db.prepare("SELECT COUNT(*) as cnt FROM thing_tags WHERE tag_name = ?").get(tag) as { cnt: number } | undefined;
    if (usage && usage.cnt === 0) {
      db.prepare("DELETE FROM tags WHERE name = ? AND published_by = 'parachute-daily'").run(tag);
    }
  }

  // Rename tools
  const toolRenames: [string, string][] = [
    ["read-daily-notes", "read-notes"],
    ["read-recent-notes", "read-recent"],
  ];
  for (const [oldName, newName] of toolRenames) {
    const oldTool = db.prepare("SELECT name FROM tools WHERE name = ?").get(oldName);
    const newTool = db.prepare("SELECT name FROM tools WHERE name = ?").get(newName);
    if (oldTool && !newTool) {
      db.prepare("DELETE FROM tools WHERE name = ?").run(oldName);
    }
  }
}
