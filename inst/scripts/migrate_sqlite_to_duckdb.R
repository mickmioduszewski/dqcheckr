# Migration script: copy an existing dqcheckr SQLite snapshot database to DuckDB.
#
# Usage (from R):
#   source(system.file("scripts/migrate_sqlite_to_duckdb.R", package = "dqcheckr"))
#   migrate_sqlite_to_duckdb("path/to/snapshots.sqlite", "path/to/snapshots.duckdb")
#
# The original SQLite file is NOT modified.  Inspect the new DuckDB file before
# switching over; then update snapshot_db in dqcheckr.yml to point to the .duckdb path.

migrate_sqlite_to_duckdb <- function(sqlite_path, duckdb_path) {
  if (!requireNamespace("RSQLite", quietly = TRUE))
    stop("RSQLite must be installed to run this migration.")
  if (!requireNamespace("DBI",     quietly = TRUE))
    stop("DBI must be installed to run this migration.")
  if (!requireNamespace("duckdb",  quietly = TRUE))
    stop("duckdb must be installed to run this migration.")

  if (!file.exists(sqlite_path))
    stop("SQLite file not found: ", sqlite_path)
  if (file.exists(duckdb_path))
    stop("DuckDB file already exists: ", duckdb_path,
         "\nDelete it first or choose a different output path.")

  src <- DBI::dbConnect(RSQLite::SQLite(), sqlite_path)
  on.exit(DBI::dbDisconnect(src), add = TRUE)

  snaps     <- DBI::dbReadTable(src, "snapshots")
  col_snaps <- DBI::dbReadTable(src, "column_snapshots")

  message("Read ", nrow(snaps), " snapshots and ",
          nrow(col_snaps), " column_snapshots from SQLite.")

  # Add new columns missing from old schema
  if (!"comparison_mode"               %in% names(snaps))
    snaps$comparison_mode               <- "comparison"
  if (!"render_status"                 %in% names(snaps))
    snaps$render_status                 <- "success"
  if (!"type_changed_cols_vs_previous" %in% names(snaps))
    snaps$type_changed_cols_vs_previous <- NA_character_

  # Rename stat key if old label is still present
  col_snaps$dq_check[col_snaps$dq_check == "numeric_mean"] <- "numeric_parseable_mean"
  col_snaps$dq_check[col_snaps$dq_check == "numeric_sd"]   <- "numeric_parseable_sd"

  dst <- DBI::dbConnect(duckdb::duckdb(), duckdb_path)
  on.exit(DBI::dbDisconnect(dst), add = TRUE)

  DBI::dbExecute(dst, "CREATE SEQUENCE IF NOT EXISTS snapshots_id_seq")
  DBI::dbExecute(dst, "CREATE SEQUENCE IF NOT EXISTS column_snapshots_id_seq")

  DBI::dbExecute(dst, "
    CREATE TABLE snapshots (
      id                            INTEGER PRIMARY KEY DEFAULT nextval('snapshots_id_seq'),
      dataset_name                  TEXT    NOT NULL,
      run_timestamp                 TEXT    NOT NULL,
      file_name                     TEXT    NOT NULL,
      row_count                     INTEGER NOT NULL,
      col_count                     INTEGER NOT NULL,
      check_pass_count              INTEGER NOT NULL DEFAULT 0,
      check_warn_count              INTEGER NOT NULL DEFAULT 0,
      check_fail_count              INTEGER NOT NULL DEFAULT 0,
      check_info_count              INTEGER NOT NULL DEFAULT 0,
      overall_status                TEXT    NOT NULL,
      new_cols_vs_previous          TEXT,
      missing_cols_vs_previous      TEXT,
      new_cols_vs_schema            TEXT,
      missing_cols_vs_schema        TEXT,
      comparison_mode               TEXT    NOT NULL DEFAULT 'comparison',
      render_status                 TEXT    NOT NULL DEFAULT 'success',
      type_changed_cols_vs_previous TEXT
    )")

  DBI::dbExecute(dst, "
    CREATE TABLE column_snapshots (
      id                 INTEGER PRIMARY KEY DEFAULT nextval('column_snapshots_id_seq'),
      snapshot_id        INTEGER NOT NULL REFERENCES snapshots(id),
      column_name        TEXT    NOT NULL,
      dq_check           TEXT    NOT NULL,
      value              TEXT,
      threshold          TEXT,
      severity_on_breach TEXT
    )")

  # Insert without id column to let the sequence assign new IDs
  snaps_no_id <- snaps[, setdiff(names(snaps), "id")]
  DBI::dbAppendTable(dst, "snapshots", snaps_no_id)

  new_snap_ids <- DBI::dbGetQuery(dst, "SELECT id FROM snapshots ORDER BY id")$id
  old_snap_ids <- sort(snaps$id)
  id_map       <- setNames(new_snap_ids, as.character(old_snap_ids))

  col_snaps_mapped <- col_snaps
  col_snaps_mapped$snapshot_id <- id_map[as.character(col_snaps$snapshot_id)]
  col_snaps_no_id  <- col_snaps_mapped[, setdiff(names(col_snaps_mapped), "id")]
  DBI::dbAppendTable(dst, "column_snapshots", col_snaps_no_id)

  message("Migration complete.")
  message("  snapshots written:        ", DBI::dbGetQuery(dst,
    "SELECT COUNT(*) AS n FROM snapshots")$n)
  message("  column_snapshots written: ", DBI::dbGetQuery(dst,
    "SELECT COUNT(*) AS n FROM column_snapshots")$n)
  message("DuckDB database: ", duckdb_path)
  invisible(duckdb_path)
}
