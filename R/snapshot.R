# Helper: open an RSQLite connection with FK enforcement enabled.
.sqlite_connect <- function(db_path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  DBI::dbExecute(con, "PRAGMA foreign_keys = ON")
  # Deployments point several datasets at one shared snapshot DB (see
  # RBB-sample/), so brief write contention between concurrent runs is normal.
  # Without a busy timeout the loser fails instantly with 'database is locked'
  # and its snapshot is swallowed into a warning; wait for the writer instead.
  # WAL journalling is deliberately NOT enabled here: it needs shared memory and
  # is unsafe on the network / OneDrive filesystems dqcheckr is deployed on.
  DBI::dbExecute(con, "PRAGMA busy_timeout = 30000")
  con
}

#' Initialise the SQLite snapshot database
#' @keywords internal
#' @noRd
init_snapshot_db <- function(db_path) {
  dir.create(dirname(db_path), recursive = TRUE, showWarnings = FALSE)
  con <- .sqlite_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  # Serialize create-and-migrate. The column check and the ALTERs must be atomic
  # with respect to other processes: two first-runs after an upgrade, sharing
  # one DB, would otherwise both read the pre-migration column list and both try
  # to ADD the same column, and the loser dies with 'duplicate column name'
  # (busy_timeout alone does not help -- the loser has already read the stale
  # list before it waits). BEGIN IMMEDIATE takes the write lock up front, so the
  # second process blocks here, then reads the already-migrated column list and
  # skips the ALTERs.
  DBI::dbExecute(con, "BEGIN IMMEDIATE")
  committed <- FALSE
  on.exit(if (!committed) try(DBI::dbExecute(con, "ROLLBACK"), silent = TRUE),
          add = TRUE, after = FALSE)

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
      type_changed_cols_vs_previous TEXT,
      report_file                   TEXT
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

  existing_cols <- DBI::dbGetQuery(
    con, "SELECT name FROM pragma_table_info('snapshots')")$name

  # Refuse to adopt a pre-existing `snapshots` table that is not ours. If the
  # file already held a table of that name from another application, the CREATE
  # above was a no-op and the ALTERs below would silently mutate the user's
  # table. Every dqcheckr schema back to 0.1.x has these core columns; their
  # absence means the table belongs to someone else. (SQLite column names are
  # case-insensitive, so compare case-folded.)
  required   <- c("dataset_name", "run_timestamp", "file_name",
                  "row_count", "col_count", "overall_status")
  have       <- tolower(existing_cols)
  if (!all(required %in% have))
    rlang::abort(
      paste0("The database at '", db_path, "' already contains a 'snapshots' ",
             "table that is not a dqcheckr snapshot table (missing: ",
             paste(setdiff(required, have), collapse = ", "),
             "). Refusing to modify it."),
      class = c("dqcheckr_schema_error", "dqcheckr_error"))

  # Auto-migrate 0.1.x databases that are missing the newer columns. Match
  # case-insensitively so a column stored as e.g. `Report_File` is recognised
  # and not re-added (which SQLite would reject as a duplicate).
  new_col_defs <- list(
    comparison_mode               = "TEXT NOT NULL DEFAULT 'comparison'",
    render_status                 = "TEXT NOT NULL DEFAULT 'success'",
    type_changed_cols_vs_previous = "TEXT",
    report_file                   = "TEXT"
  )
  for (col_name in names(new_col_defs)) {
    if (!tolower(col_name) %in% have)
      DBI::dbExecute(con, sprintf("ALTER TABLE snapshots ADD COLUMN %s %s",
                                  col_name, new_col_defs[[col_name]]))
  }

  DBI::dbExecute(con, "COMMIT")
  committed <- TRUE
  invisible(db_path)
}

#' Mark a snapshot's render_status as failed
#'
#' Also clears report_file so a row can never name a report that was not written:
#' render_status = 'failed' is the guard consumers key on, and report_file is
#' NULLed to stay consistent with it. report_file is only ever set (by
#' \code{.set_report_file}) after a report is confirmed written, so on this path
#' it is already NULL -- the clear is belt-and-braces.
#' @keywords internal
#' @noRd
.mark_render_failed <- function(db_path, snapshot_id) {
  tryCatch({
    con <- .sqlite_connect(db_path)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    DBI::dbExecute(con,
      "UPDATE snapshots SET render_status = 'failed', report_file = NULL WHERE id = ?",
      list(snapshot_id))
  }, error = function(e)
    # A silent failure here is the bug this guard exists to prevent: the row
    # would keep its INSERT-time render_status = 'pending' for a report that was
    # never written, instead of being flipped to 'failed'.
    warning("Could not mark snapshot ", snapshot_id, " as render-failed; its ",
            "render_status may still read 'pending': ", conditionMessage(e),
            call. = FALSE))
}

#' Mark a snapshot's render as succeeded and record the report filename
#'
#' The post-render UPDATE for the success path: it flips render_status from the
#' INSERT-time 'pending' to 'success' and records the filename in one statement.
#' Both are written here (not at INSERT) so the filename can carry the snapshot
#' id -- known only after the row exists -- and so the row never advertises
#' 'success' with a report_file for a report that has not been written yet
#' (B-42, B-04).
#' @keywords internal
#' @noRd
.set_report_file <- function(db_path, snapshot_id, report_file) {
  tryCatch({
    con <- .sqlite_connect(db_path)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    DBI::dbExecute(con,
      "UPDATE snapshots SET render_status = 'success', report_file = ? WHERE id = ?",
      list(report_file, snapshot_id))
  }, error = function(e)
    warning("Could not record report filename for snapshot ", snapshot_id,
            "; the history link may be missing: ", conditionMessage(e),
            call. = FALSE))
}

#' Serialise a numeric aggregate for the snapshot DB, mapping non-finite to NA
#'
#' The invariant this enforces: no value written to \code{column_snapshots} may
#' be a non-finite literal ("Inf", "-Inf", "NaN"). Those are read back by the
#' drift path (\code{.safe_num} in drift.R) and would poison the comparison. A
#' result can be non-finite from a non-finite \emph{input} (guarded separately by
#' the \code{is.finite(vals)} filter in \code{compute_col_stats}) OR from
#' overflow in the aggregate \emph{itself} -- e.g. \code{sd()} of finite but very
#' large values squares past the double range and returns \code{Inf}. This is the
#' output-side guard; the input filter is the input-side one. Both are needed.
#' @keywords internal
#' @noRd
.finite_or_na <- function(v) {
  if (length(v) == 1L && is.finite(v)) as.character(v) else NA_character_
}

#' Compute per-column statistics for snapshot storage
#' @keywords internal
#' @noRd
#' @importFrom stats sd
compute_col_stats <- function(df, config, types = NULL) {
  types <- types %||% resolve_col_types(df, config)
  col_frames <- lapply(names(df), function(col) {
    x          <- df[[col]]
    col_type   <- types[[col]]
    non_empty  <- x[!.missing_vals(x)]
    miss_count <- sum(.missing_vals(x))
    # Defined as 0 for a zero-row frame; 0/0 would store literal "NaN" in the
    # snapshot DB and poison drift arithmetic.
    miss_rate  <- if (nrow(df) > 0) miss_count / nrow(df) else 0
    dist_count <- length(unique(non_empty))

    miss_threshold <- col_threshold(config, col, "max_missing_rate", 0.05)

    # Parallel vectors, one data.frame per column -- not one per stat row.
    checks     <- c("inferred_type", "missing_count", "missing_rate",
                    "distinct_count")
    values     <- c(col_type, as.character(miss_count),
                    as.character(miss_rate), as.character(dist_count))
    thresholds <- c(NA_character_, NA_character_,
                    as.character(miss_threshold), NA_character_)
    severities <- c(NA_character_, NA_character_, "FAIL", NA_character_)

    if (col_type == "numeric") {
      vals <- suppressWarnings(as.numeric(x))
      # Non-finite parses (Inf/-Inf from a corrupted delivery -- write.csv emits
      # the literal "Inf") are excluded from the aggregates here (input side);
      # the aggregates themselves are serialised through .finite_or_na (output
      # side), because sd()/mean() of finite-but-huge values can still overflow
      # to Inf. A literal "Inf"/"NaN" in the snapshot DB poisons drift arithmetic.
      nn   <- vals[is.finite(vals)]
      nn_count <- sum(!is.na(non_empty) &
                      is.na(suppressWarnings(as.numeric(non_empty))))
      nn_rate  <- if (length(non_empty) > 0) nn_count / length(non_empty) else 0
      nn_threshold <- col_threshold(config, col, "max_non_numeric_rate", 0.01)

      checks     <- c(checks,
                      "numeric_parseable_mean", "numeric_sd",
                      "numeric_min", "numeric_max",
                      "non_numeric_count", "non_numeric_rate")
      values     <- c(values,
                      if (length(nn) > 0) .finite_or_na(mean(nn)) else NA_character_,
                      if (length(nn) > 1) .finite_or_na(sd(nn))   else NA_character_,
                      if (length(nn) > 0) .finite_or_na(min(nn))  else NA_character_,
                      if (length(nn) > 0) .finite_or_na(max(nn))  else NA_character_,
                      as.character(nn_count),
                      as.character(nn_rate))
      thresholds <- c(thresholds,
                      NA_character_, NA_character_, NA_character_, NA_character_,
                      NA_character_, as.character(nn_threshold))
      severities <- c(severities,
                      NA_character_, NA_character_, NA_character_, NA_character_,
                      NA_character_, "FAIL")
    }

    data.frame(column_name = col, dq_check = checks, value = values,
               threshold = thresholds, severity_on_breach = severities,
               stringsAsFactors = FALSE)
  })

  # A zero-column delivery (e.g. an empty file) yields no per-column frames;
  # do.call(rbind, list()) is NULL, which would make write_snapshot() fail on
  # col_stats$snapshot_id<- and lose the whole snapshot row. Return an empty
  # frame with the expected schema so the run is still recorded.
  if (length(col_frames) == 0) {
    return(data.frame(
      column_name = character(0), dq_check = character(0),
      value = character(0), threshold = character(0),
      severity_on_breach = character(0), stringsAsFactors = FALSE))
  }
  do.call(rbind, col_frames)
}

#' Write a run snapshot to the SQLite database
#' @keywords internal
#' @noRd
write_snapshot <- function(db_path, dataset_name, file_name, df,
                           qc_results, cp_results, custom_results, config,
                           col_stats = NULL,
                           comparison_mode = "comparison",
                           run_time = NULL) {
  # One clock read per run: run_dq_check() passes the same run_time here and
  # to render_report() so the report filename reconstructed from the stored
  # run_timestamp (e.g. by the GUI) always matches the file actually written.
  # report_file is NOT written here: it is always NULL at INSERT and is only set
  # by .set_report_file() after the report is confirmed written, so the column
  # can never name a report that was not written (the invariant is structural,
  # not caller-enforced). Render failures are flagged via render_status.
  run_time <- run_time %||% Sys.time()
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

    expected <- config[["expected_columns"]]
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

    if (is.null(col_stats)) col_stats <- compute_col_stats(df, config)

    # All writes in one transaction: a failure part-way (disk full, malformed
    # value) must not leave a snapshots row without its column_snapshots stats,
    # which would silently poison later drift comparisons.
    #
    # render_status is inserted as 'pending', not 'success': the row is committed
    # here, before the report is rendered, and is only flipped to 'success' by
    # .set_report_file() once the report is confirmed written (or to 'failed' by
    # .mark_render_failed()). A concurrent reader during the render window then
    # sees 'pending' -- distinguishable from a finished row -- instead of a
    # premature 'success' with a NULL report_file that looks like a completed
    # pre-0.2.3 row (B-04). The schema DEFAULT stays 'success' because it applies
    # only to legacy rows backfilled by the ALTER-TABLE migration, which did
    # render successfully under the old flow.
    DBI::dbWithTransaction(con, {
      DBI::dbExecute(con,
        "INSERT INTO snapshots
         (dataset_name, run_timestamp, file_name, row_count, col_count,
          check_pass_count, check_warn_count, check_fail_count, check_info_count,
          overall_status,
          new_cols_vs_previous, missing_cols_vs_previous,
          new_cols_vs_schema, missing_cols_vs_schema,
          comparison_mode, render_status, type_changed_cols_vs_previous)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)",
        list(dataset_name,
             format(run_time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
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

      # A zero-column delivery yields no per-column stats; assigning a scalar
      # snapshot_id to a 0-row frame errors, so skip the append entirely and
      # still record the snapshots row.
      if (nrow(col_stats) > 0) {
        col_stats$snapshot_id <- snapshot_id
        DBI::dbAppendTable(con, "column_snapshots",
          col_stats[, c("snapshot_id", "column_name", "dq_check",
                        "value", "threshold", "severity_on_breach")])
      }

      custom_col <- Filter(function(r) !is.na(r$column), custom_results)
      if (length(custom_col) > 0) {
        DBI::dbAppendTable(con, "column_snapshots", data.frame(
          snapshot_id = snapshot_id,
          column_name = vapply(custom_col, `[[`, character(1), "column"),
          dq_check    = vapply(custom_col, `[[`, character(1), "check_id"),
          value       = vapply(custom_col, `[[`, character(1), "observed"),
          threshold   = vapply(custom_col, `[[`, character(1), "threshold"),
          severity_on_breach = vapply(custom_col, function(r)
            if (r$status %in% c("WARN", "FAIL")) r$status else NA_character_,
            character(1)),
          stringsAsFactors = FALSE
        ))
      }

      snapshot_id
    })
  },
  error = function(e) {
    # Non-fatal by design: the run continues without a snapshot. The message is
    # cause-neutral because this block also covers init/migration and status
    # computation, not only the INSERT -- run_dq_check() surfaces the resulting
    # NULL snapshot_id in its final line so the loss is not silent.
    warning("Snapshot not recorded (SQLite write failed): ", conditionMessage(e),
            call. = FALSE)
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
#'   \code{render_status}, \code{type_changed_cols_vs_previous}, and
#'   \code{report_file} (the rendered report's filename, \code{NA} for
#'   snapshots written before dqcheckr 0.2.3).
#'   \code{render_status} is one of \code{"pending"} (0.2.5+: the row was written
#'   but its report has not finished rendering yet -- \code{report_file} is
#'   \code{NA} in this window), \code{"success"} (report written;
#'   \code{report_file} names it), or \code{"failed"} (render skipped or errored;
#'   \code{report_file} is \code{NA}). Consumers linking to a report should treat
#'   a \code{"pending"} row as not-yet-available rather than reconstructing a
#'   filename for a report that does not exist.
#'   Returns an empty data frame with the same columns if the database does
#'   not exist or contains no records for the dataset. If the database exists
#'   but cannot be read (corrupt file, permissions, an unresolved lock), it
#'   emits a warning naming the cause and returns the same empty data frame, so
#'   a read failure is visible rather than masquerading as an empty history.
#'
#' @examples
#' history <- read_recent_snapshots(tempfile(fileext = ".sqlite"), "starwars_csv")
#'
#' @export
read_recent_snapshots <- function(db_path, dataset_name, n = 10) {
  # Kept in sync with the snapshots table schema (init_snapshot_db) so code
  # branching on any column behaves identically on the no-database path.
  empty <- data.frame(
    id = integer(), dataset_name = character(), run_timestamp = character(),
    file_name = character(), row_count = integer(), col_count = integer(),
    check_pass_count = integer(), check_warn_count = integer(),
    check_fail_count = integer(), check_info_count = integer(),
    overall_status = character(), new_cols_vs_previous = character(),
    missing_cols_vs_previous = character(), new_cols_vs_schema = character(),
    missing_cols_vs_schema = character(), comparison_mode = character(),
    render_status = character(), type_changed_cols_vs_previous = character(),
    report_file = character(),
    stringsAsFactors = FALSE
  )

  if (!file.exists(db_path)) return(empty)

  tryCatch({
    con <- .sqlite_connect(db_path)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    if (!"snapshots" %in% DBI::dbListTables(con)) return(empty)
    res <- DBI::dbGetQuery(con,
      "SELECT * FROM snapshots
       WHERE dataset_name = ?
       ORDER BY id DESC
       LIMIT ?",
      list(dataset_name, as.integer(n)))

    # Backfill columns a pre-0.2.3 database predates. SELECT * returns only the
    # columns that physically exist, so an un-migrated DB yields a frame that is
    # *missing* these columns outright -- consumers branching on report_file (or
    # the 0.1.x-era columns) would error rather than see NA. We do NOT ALTER the
    # table here: a read must not mutate the file (read-only shares, the NSW
    # OneDrive deployment) nor race a concurrent write. Instead fill each absent
    # column with exactly the value ALTER TABLE ... DEFAULT would have written,
    # so the same database reads identically before and after its first 0.2.3+
    # write. rep(..., nrow(res)) keeps a zero-row result correctly typed.
    defaults <- list(comparison_mode = "comparison", render_status = "success")
    for (col in setdiff(names(empty), names(res))) {
      fill <- defaults[[col]] %||% empty[[col]][NA_integer_]  # typed NA otherwise
      res[[col]] <- rep(fill, nrow(res))
    }
    res[, names(empty), drop = FALSE]  # pin column order to the schema
  },
  error = function(e) {
    # A read failure (corrupt file, permissions, a lock that outlasted the busy
    # timeout) is NOT the same as "no history yet". Returning empty silently
    # would tell the caller there are no runs when the truth is the read failed,
    # so surface it as a warning before falling back to the empty frame.
    warning("Could not read snapshot history from '", db_path, "': ",
            conditionMessage(e), call. = FALSE)
    empty
  })
}
