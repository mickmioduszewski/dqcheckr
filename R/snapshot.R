# Helper: open an RSQLite connection with FK enforcement enabled.
.sqlite_connect <- function(db_path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  con
}

#' Initialise the SQLite snapshot database
#' @keywords internal
#' @noRd
init_snapshot_db <- function(db_path) {
  dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)
  con <- .sqlite_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS snapshots (
      id                            INTEGER PRIMARY KEY AUTOINCREMENT,
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
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS column_snapshots (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      snapshot_id        INTEGER NOT NULL REFERENCES snapshots(id),
      column_name        TEXT    NOT NULL,
      dq_check           TEXT    NOT NULL,
      value              TEXT,
      threshold          TEXT,
      severity_on_breach TEXT
    )
  ")

  # Auto-migrate 0.1.x databases that are missing the new columns.
  existing_cols <- DBI::dbGetQuery(
    con, "SELECT name FROM pragma_table_info('snapshots')")$name
  new_col_defs <- list(
    comparison_mode               = "TEXT NOT NULL DEFAULT 'comparison'",
    render_status                 = "TEXT NOT NULL DEFAULT 'success'",
    type_changed_cols_vs_previous = "TEXT"
  )
  for (col_name in names(new_col_defs)) {
    if (!col_name %in% existing_cols)
      DBI::dbExecute(con, sprintf("ALTER TABLE snapshots ADD COLUMN %s %s",
                                  col_name, new_col_defs[[col_name]]))
  }

  invisible(db_path)
}

#' Mark a snapshot's render_status as failed
#' @keywords internal
#' @noRd
.mark_render_failed <- function(db_path, snapshot_id) {
  tryCatch({
    con <- .sqlite_connect(db_path)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    DBI::dbExecute(con,
      "UPDATE snapshots SET render_status = 'failed' WHERE id = ?",
      list(snapshot_id))
  }, error = function(e) invisible(NULL))
}

#' Compute per-column statistics for snapshot storage
#' @keywords internal
#' @noRd
#' @importFrom stats sd
compute_col_stats <- function(df, config) {
  col_frames <- lapply(names(df), function(col) {
    x          <- df[[col]]
    col_type   <- resolve_col_type(col, x, config)
    non_empty  <- x[!is.na(x) & x != ""]
    miss_count <- sum(is.na(x) | x == "")
    miss_rate  <- miss_count / nrow(df)
    dist_count <- length(unique(non_empty))

    miss_threshold <- col_threshold(config, col, "max_missing_rate", 0.05)

    stat_rows <- list(
      data.frame(column_name = col, dq_check = "inferred_type",
                 value = col_type, threshold = NA_character_,
                 severity_on_breach = NA_character_, stringsAsFactors = FALSE),
      data.frame(column_name = col, dq_check = "missing_count",
                 value = as.character(miss_count), threshold = NA_character_,
                 severity_on_breach = NA_character_, stringsAsFactors = FALSE),
      data.frame(column_name = col, dq_check = "missing_rate",
                 value = as.character(miss_rate),
                 threshold = as.character(miss_threshold),
                 severity_on_breach = "FAIL", stringsAsFactors = FALSE),
      data.frame(column_name = col, dq_check = "distinct_count",
                 value = as.character(dist_count), threshold = NA_character_,
                 severity_on_breach = NA_character_, stringsAsFactors = FALSE)
    )

    if (col_type == "numeric") {
      vals <- suppressWarnings(as.numeric(x))
      nn   <- vals[!is.na(vals)]
      nn_count <- sum(!is.na(non_empty) &
                      is.na(suppressWarnings(as.numeric(non_empty))))
      nn_rate  <- if (length(non_empty) > 0) nn_count / length(non_empty) else 0
      nn_threshold <- col_threshold(config, col, "max_non_numeric_rate", 0.01)

      stat_rows <- c(stat_rows, list(
        data.frame(column_name = col, dq_check = "numeric_parseable_mean",
                   value = if (length(nn) > 0) as.character(mean(nn)) else NA_character_,
                   threshold = NA_character_, severity_on_breach = NA_character_,
                   stringsAsFactors = FALSE),
        data.frame(column_name = col, dq_check = "numeric_sd",
                   value = if (length(nn) > 1) as.character(sd(nn)) else NA_character_,
                   threshold = NA_character_, severity_on_breach = NA_character_,
                   stringsAsFactors = FALSE),
        data.frame(column_name = col, dq_check = "numeric_min",
                   value = if (length(nn) > 0) as.character(min(nn)) else NA_character_,
                   threshold = NA_character_, severity_on_breach = NA_character_,
                   stringsAsFactors = FALSE),
        data.frame(column_name = col, dq_check = "numeric_max",
                   value = if (length(nn) > 0) as.character(max(nn)) else NA_character_,
                   threshold = NA_character_, severity_on_breach = NA_character_,
                   stringsAsFactors = FALSE),
        data.frame(column_name = col, dq_check = "non_numeric_count",
                   value = as.character(nn_count), threshold = NA_character_,
                   severity_on_breach = NA_character_, stringsAsFactors = FALSE),
        data.frame(column_name = col, dq_check = "non_numeric_rate",
                   value = as.character(nn_rate),
                   threshold = as.character(nn_threshold),
                   severity_on_breach = "FAIL", stringsAsFactors = FALSE)
      ))
    }

    do.call(rbind, stat_rows)
  })

  do.call(rbind, col_frames)
}

#' Write a run snapshot to the SQLite database
#' @keywords internal
#' @noRd
write_snapshot <- function(db_path, dataset_name, file_name, df,
                           qc_results, cp_results, custom_results, config,
                           col_stats = NULL,
                           comparison_mode = "comparison") {
  tryCatch({
    init_snapshot_db(db_path)
    con <- .sqlite_connect(db_path)
    on.exit(DBI::dbDisconnect(con), add = TRUE)

    all_results <- c(qc_results, cp_results, custom_results)
    statuses    <- vapply(all_results, `[[`, character(1), "status")

    pass_count <- sum(statuses == "PASS")
    warn_count <- sum(statuses == "WARN")
    fail_count <- sum(statuses == "FAIL")
    info_count <- sum(statuses == "INFO")
    o_status   <- overall_status(all_results)

    new_cols_prev  <- attr(cp_results, "new_cols")
    drop_cols_prev <- attr(cp_results, "dropped_cols")
    type_chg_cols  <- attr(cp_results, "type_changed_cols")
    new_cols_prev_str  <- if (length(new_cols_prev) > 0)
      paste(new_cols_prev,  collapse = ",") else NA_character_
    drop_cols_prev_str <- if (length(drop_cols_prev) > 0)
      paste(drop_cols_prev, collapse = ",") else NA_character_
    type_chg_str       <- if (length(type_chg_cols) > 0)
      paste(type_chg_cols,  collapse = ",") else NA_character_

    expected <- config$expected_columns
    if (!is.null(expected)) {
      sc01_fail <- Filter(\(r) r$check_id == "SC-01" && r$status == "FAIL",
                          qc_results)
      sc02_fail <- Filter(\(r) r$check_id == "SC-02" && r$status == "FAIL",
                          qc_results)
      new_schema  <- if (length(sc01_fail) > 0)
        paste(vapply(sc01_fail, \(r) r$column, character(1)), collapse = ",")
      else NA_character_
      miss_schema <- if (length(sc02_fail) > 0)
        paste(vapply(sc02_fail, \(r) r$column, character(1)), collapse = ",")
      else NA_character_
    } else {
      new_schema  <- NA_character_
      miss_schema <- NA_character_
    }

    DBI::dbExecute(con,
      "INSERT INTO snapshots
       (dataset_name, run_timestamp, file_name, row_count, col_count,
        check_pass_count, check_warn_count, check_fail_count, check_info_count,
        overall_status,
        new_cols_vs_previous, missing_cols_vs_previous,
        new_cols_vs_schema, missing_cols_vs_schema,
        comparison_mode, render_status, type_changed_cols_vs_previous)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'success', ?)",
      list(dataset_name,
           format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
           file_name,
           nrow(df), ncol(df),
           pass_count, warn_count, fail_count, info_count,
           o_status,
           new_cols_prev_str, drop_cols_prev_str,
           new_schema, miss_schema,
           comparison_mode,
           type_chg_str)
    )

    snapshot_id <- DBI::dbGetQuery(con,
      "SELECT last_insert_rowid() AS id")$id[[1]]

    if (is.null(col_stats)) col_stats <- compute_col_stats(df, config)
    col_stats$snapshot_id <- snapshot_id

    DBI::dbAppendTable(con, "column_snapshots",
      col_stats[, c("snapshot_id", "column_name", "dq_check",
                    "value", "threshold", "severity_on_breach")])

    for (r in custom_results) {
      if (!is.na(r$column)) {
        sev <- if (r$status %in% c("WARN", "FAIL")) r$status else NA_character_
        DBI::dbExecute(con,
          "INSERT INTO column_snapshots
           (snapshot_id, column_name, dq_check, value, threshold, severity_on_breach)
           VALUES (?, ?, ?, ?, ?, ?)",
          list(snapshot_id, r$column, r$check_id,
               r$observed, r$threshold, sev))
      }
    }

    snapshot_id
  },
  error = function(e) {
    warning("SQLite write failed: ", conditionMessage(e))
    NULL
  })
}

#' Read recent snapshot history from the SQLite database
#'
#' Retrieves the \code{n} most recent run records for a given dataset from the
#' snapshot database, ordered newest-first.
#'
#' @param db_path Character. Path to the SQLite database file.
#' @param dataset_name Character. Dataset name to filter on.
#' @param n Integer. Maximum number of records to return. Defaults to 10.
#'
#' @return A data frame with one row per run and columns including
#'   \code{id}, \code{dataset_name}, \code{run_timestamp}, \code{file_name},
#'   \code{row_count}, \code{col_count}, \code{overall_status},
#'   \code{check_pass_count}, \code{check_warn_count}, \code{check_fail_count},
#'   \code{check_info_count}, \code{new_cols_vs_previous},
#'   \code{missing_cols_vs_previous}, \code{new_cols_vs_schema},
#'   \code{missing_cols_vs_schema}, \code{comparison_mode},
#'   \code{render_status}, and \code{type_changed_cols_vs_previous}.
#'   Returns an empty data frame if the database does not exist or contains no
#'   records for the dataset.
#'
#' @examples
#' history <- read_recent_snapshots(tempfile(fileext = ".sqlite"), "starwars_csv")
#'
#' @export
read_recent_snapshots <- function(db_path, dataset_name, n = 10) {
  empty <- data.frame(
    id = integer(), dataset_name = character(), run_timestamp = character(),
    file_name = character(), row_count = integer(), col_count = integer(),
    check_pass_count = integer(), check_warn_count = integer(),
    check_fail_count = integer(), check_info_count = integer(),
    overall_status = character(), new_cols_vs_previous = character(),
    missing_cols_vs_previous = character(), new_cols_vs_schema = character(),
    missing_cols_vs_schema = character(),
    stringsAsFactors = FALSE
  )

  if (!file.exists(db_path)) return(empty)

  tryCatch({
    con <- .sqlite_connect(db_path)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    if (!"snapshots" %in% DBI::dbListTables(con)) return(empty)
    DBI::dbGetQuery(con,
      "SELECT * FROM snapshots
       WHERE dataset_name = ?
       ORDER BY id DESC
       LIMIT ?",
      list(dataset_name, as.integer(n)))
  },
  error = function(e) empty)
}
