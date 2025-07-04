import os, osproc, sequtils, algorithm
import db_connector/db_sqlite

proc ensureMigrationTable(db: DbConn) =
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS schema_migrations (
      filename TEXT PRIMARY KEY,
      applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  """)

proc hasMigrationRun(db: DbConn, filename: string): bool =
  for row in db.fastRows(sql"SELECT 1 FROM schema_migrations WHERE filename = ?", filename):
    return true
  return false

proc markMigrationRun(db: DbConn, filename: string) =
  db.exec(sql"INSERT INTO schema_migrations (filename) VALUES (?)", filename)

proc runMigrations*(db: DbConn, dir = "migrations") =
  ensureMigrationTable(db)
  let files = walkFiles(dir / "*.sql").toSeq().sorted()
  for file in files:
    if hasMigrationRun(db, file):
      echo "Already applied: ", file
    else:
      echo "Applying: ", file
      let sql = readFile(file)
      db.exec(sql(sql))
      markMigrationRun(db, file)

proc main() =
  let db = open("test.db", "", "", "")
  try:
    runMigrations(db)
  finally:
    db.close()

when isMainModule:
  main()