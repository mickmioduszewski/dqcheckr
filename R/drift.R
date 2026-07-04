#' List snapshots available in the database
#'
#' Returns a data frame of snapshot records for the given dataset (or all
#' datasets if \code{dataset_name} is \code{NULL}), ordered by dataset name
#' and snapshot ID.
#'
#' @param dataset_name Character or \code{NULL}. If supplied, only snapshots for
#'   that dataset are returned. If \code{NULL}, all datasets are returned.
#' @param db_path Character. Path to the SQLite snapshot database. Required;
#'   there is no default (a relative default would be path-sensitive).
#'
#' @return A data frame with columns \code{id}, \code{dataset_name},
#'   \code{file_name}, \code{run_timestamp}, \code{row_count},
#'   \code{overall_status}. Returns an empty data frame if the database does not
#'   exist or contains no matching records.
#'
#' @examples
#' list_snapshots(db_path = tempfile(fileext = ".sqlite"))
#'
#' @export
list_snapshots <- function(dataset_name = NULL,
                           db_path = NULL) {
  if (is.null(db_path))
    rlang::abort('`db_path` must be supplied (e.g. db_path = "data/snapshots.sqlite")',
                 class = c("dqcheckr_invalid_argument", "dqcheckr_error"))
  empty <- data.frame(
    id = integer(), dataset_name = character(), file_name = character(),
    run_timestamp = character(), row_count = integer(),
    overall_status = character(), stringsAsFactors = FALSE
  )
  if (!file.exists(db_path)) return(invisible(empty))

  tryCatch({
    con <- .sqlite_connect(db_path)
    on.exit(DBI::dbDisconnect(con), add = TRUE)
    if (!"snapshots" %in% DBI::dbListTables(con)) return(invisible(empty))

    if (is.null(dataset_name)) {
      DBI::dbGetQuery(con,
        "SELECT id, dataset_name, file_name, run_timestamp, row_count,
                overall_status
         FROM snapshots
         ORDER BY dataset_name, id")
    } else {
      DBI::dbGetQuery(con,
        "SELECT id, dataset_name, file_name, run_timestamp, row_count,
                overall_status
         FROM snapshots
         WHERE dataset_name = ?
         ORDER BY id",
        list(dataset_name))
    }
  },
  error = function(e) invisible(empty))
}

#' Compare two snapshots from the SQLite database
#'
#' Reads two historical snapshot records (by ID) from the SQLite database and
#' computes table-level, schema, and per-column statistical drift. Optionally
#' renders an HTML drift report.
#'
#' @param dataset_name Character. Dataset name to compare.
#' @param snapshot_id_prev Integer or \code{NULL}. ID of the earlier snapshot.
#'   If \code{NULL}, defaults to the second-most-recent snapshot by ID.
#' @param snapshot_id_curr Integer or \code{NULL}. ID of the later snapshot.
#'   If \code{NULL}, defaults to the most-recent snapshot by ID.
#' @param db_path Character or \code{NULL}. Path to the SQLite snapshot
#'   database. If \code{NULL} (the default), the path is read from
#'   \code{snapshot_db} in \code{dqcheckr.yml}.
#' @param config_dir Character. Path to the directory containing
#'   \code{dqcheckr.yml}. Used to read thresholds, \code{report_output_dir},
#'   and (when \code{db_path} is \code{NULL}) \code{snapshot_db}.
#' @param report Logical. Whether to render an HTML drift report.
#' @param open_report Logical. Whether to open the HTML report in the browser
#'   after rendering (only takes effect in interactive sessions).
#'
#' @return Invisibly, a named list with elements \code{dataset_name},
#'   \code{snap_prev}, \code{snap_curr}, \code{table_drift},
#'   \code{schema_changes}, \code{missing_rate_changes},
#'   \code{non_numeric_changes}, \code{mean_shifts}, \code{distinct_changes}.
#'
#' @examples
#' \donttest{
#' tmp     <- tempdir()
#' db_path <- file.path(tmp, "snap.sqlite")
#' cfg_yml <- file.path(tmp, "dqcheckr.yml")
#' ds_yml  <- file.path(tmp, "starwars_csv.yml")
#' dat     <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' writeLines(c(
#'   paste0('snapshot_db: "', db_path, '"'),
#'   paste0('report_output_dir: "', tmp, '"'),
#'   'default_rules:',
#'   '  max_missing_rate: 0.60',
#'   '  min_row_count: 80'
#' ), cfg_yml)
#' writeLines(c(
#'   'dataset_name: "starwars_csv"',
#'   paste0('current_file: "', dat, '"'),
#'   'format: csv',
#'   'encoding: "UTF-8"',
#'   'delimiter: ","'
#' ), ds_yml)
#' run_dq_check("starwars_csv", config_dir = tmp, open_report = FALSE)
#' run_dq_check("starwars_csv", config_dir = tmp, open_report = FALSE)
#' drift <- compare_snapshots("starwars_csv", config_dir = tmp, report = FALSE)
#' names(drift)
#' }
#'
#' @export
compare_snapshots <- function(dataset_name,
                              snapshot_id_prev = NULL,
                              snapshot_id_curr = NULL,
                              db_path          = NULL,
                              config_dir       = ".",
                              report           = TRUE,
                              open_report      = interactive()) {
  ds_yml <- file.path(config_dir, paste0(dataset_name, ".yml"))
  thresholds <- if (file.exists(ds_yml)) {
    cfg <- load_config(dataset_name, config_dir)
    list(
      snapshot_db                    = cfg$snapshot_db %||% "data/snapshots.sqlite",
      report_output_dir              = cfg$report_output_dir %||% "reports/",
      max_missing_rate_change_pp     = cfg$rules$max_missing_rate_change_pp     %||% 2.0,
      max_numeric_mean_shift_pct     = cfg$rules$max_numeric_mean_shift_pct     %||% 0.20,
      max_non_numeric_rate_change_pp = cfg$rules$max_non_numeric_rate_change_pp %||% 1.0,
      max_row_count_change_pct       = cfg$rules$max_row_count_change_pct       %||% 0.10
    )
  } else {
    .load_drift_thresholds(config_dir)
  }
  report_dir <- thresholds$report_output_dir

  if (is.null(db_path))
    db_path <- normalizePath(thresholds$snapshot_db, mustWork = FALSE)

  if (!file.exists(db_path))
    rlang::abort(paste0("Snapshot database not found: ", db_path),
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))

  con <- .sqlite_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)

  snaps <- DBI::dbGetQuery(con,
    "SELECT * FROM snapshots WHERE dataset_name = ? ORDER BY id",
    list(dataset_name))

  if (nrow(snaps) < 2)
    rlang::abort(sprintf(
      "Need at least 2 snapshots for '%s'. Found %d.",
      dataset_name, nrow(snaps)
    ), class = c("dqcheckr_not_found", "dqcheckr_error"))

  id_prev <- snapshot_id_prev %||% snaps$id[nrow(snaps) - 1]
  id_curr <- snapshot_id_curr %||% snaps$id[nrow(snaps)]

  if (id_prev == id_curr)
    rlang::abort("snapshot_id_prev and snapshot_id_curr must differ.",
                 class = c("dqcheckr_invalid_argument", "dqcheckr_error"))

  if (id_prev > id_curr)
    rlang::abort(
      "snapshot_id_prev must be older than snapshot_id_curr (lower ID first).",
      class = c("dqcheckr_invalid_argument", "dqcheckr_error")
    )

  drift <- .compute_drift(con, dataset_name, id_prev, id_curr, thresholds)

  html_path <- NULL

  if (report) {
    ts        <- format(Sys.time(), "%Y%m%d_%H%M%S", tz = "UTC")
    base_name <- sprintf("drift_%s_%s", dataset_name, ts)
    dir.create(report_dir, showWarnings = FALSE, recursive = TRUE)
    html_path <- file.path(report_dir, paste0(base_name, ".html"))
    # NULL when Quarto is unavailable — the message and browseURL below must
    # not reference a report that was never written.
    html_path <- .write_drift_html_report(drift, html_path)
  }

  message(sprintf(
    "[dqcheckr] drift: %s snapshot #%d vs #%d%s",
    dataset_name, id_prev, id_curr,
    if (!is.null(html_path)) paste0(" | ", html_path) else ""
  ))

  if (open_report && report && !is.null(html_path) && interactive())
    utils::browseURL(html_path)

  invisible(drift)
}

# --- Internal helpers ----------------------------------------------------------

.load_drift_thresholds <- function(config_dir = ".") {
  cfg_file <- file.path(config_dir, "dqcheckr.yml")
  if (!file.exists(cfg_file))
    rlang::abort(paste0("Global config not found: ", cfg_file),
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))

  cfg <- yaml::read_yaml(cfg_file)
  dr  <- cfg$default_rules %||% list()

  list(
    snapshot_db                    = cfg$snapshot_db %||% "data/snapshots.sqlite",
    report_output_dir              = cfg$report_output_dir %||% "reports/",
    max_missing_rate_change_pp     = dr$max_missing_rate_change_pp     %||% 2.0,
    max_numeric_mean_shift_pct     = dr$max_numeric_mean_shift_pct     %||% 0.20,
    max_non_numeric_rate_change_pp = dr$max_non_numeric_rate_change_pp %||% 1.0,
    max_row_count_change_pct       = dr$max_row_count_change_pct       %||% 0.10
  )
}

.get_col_stats <- function(con, snapshot_id) {
  DBI::dbGetQuery(con,
    "SELECT column_name, dq_check, value
     FROM column_snapshots WHERE snapshot_id = ?",
    list(snapshot_id))
}

.safe_num <- function(x) suppressWarnings(as.numeric(x))

.compute_drift <- function(con, dataset_name, id_prev, id_curr, thresholds) {
  snaps <- DBI::dbGetQuery(con,
    "SELECT * FROM snapshots WHERE id IN (?, ?)",
    list(id_prev, id_curr))

  snap_prev <- snaps[snaps$id == id_prev, ]
  snap_curr <- snaps[snaps$id == id_curr, ]

  if (nrow(snap_prev) == 0)
    rlang::abort(sprintf("Snapshot ID %d not found.", id_prev),
                 class = c("dqcheckr_not_found", "dqcheckr_error"))
  if (nrow(snap_curr) == 0)
    rlang::abort(sprintf("Snapshot ID %d not found.", id_curr),
                 class = c("dqcheckr_not_found", "dqcheckr_error"))

  stats_prev <- .get_col_stats(con, id_prev)
  stats_curr <- .get_col_stats(con, id_curr)

  row_change_pct <- (snap_curr$row_count - snap_prev$row_count) /
                    snap_prev$row_count

  table_drift <- data.frame(
    Metric   = c("Row count", "Column count",
                 "Checks PASS", "Checks WARN", "Checks FAIL", "Checks INFO"),
    Previous = c(snap_prev$row_count,        snap_prev$col_count,
                 snap_prev$check_pass_count,  snap_prev$check_warn_count,
                 snap_prev$check_fail_count,  snap_prev$check_info_count),
    Current  = c(snap_curr$row_count,        snap_curr$col_count,
                 snap_curr$check_pass_count,  snap_curr$check_warn_count,
                 snap_curr$check_fail_count,  snap_curr$check_info_count),
    stringsAsFactors = FALSE
  )
  table_drift$Change     <- table_drift$Current - table_drift$Previous
  table_drift$Change_pct <- ifelse(
    table_drift$Previous != 0,
    sprintf("%+.1f%%",
            (table_drift$Current - table_drift$Previous) /
            table_drift$Previous * 100),
    "N/A"
  )
  table_drift$Exceeds    <- ""
  table_drift$Exceeds[1] <- ifelse(
    abs(row_change_pct) > thresholds$max_row_count_change_pct, "***", ""
  )

  types_prev <- stats_prev[stats_prev$dq_check == "inferred_type",
                            c("column_name", "value")]
  types_curr <- stats_curr[stats_curr$dq_check == "inferred_type",
                            c("column_name", "value")]
  names(types_prev) <- c("Column", "Type_Previous")
  names(types_curr) <- c("Column", "Type_Current")

  schema_all <- merge(types_prev, types_curr, by = "Column", all = TRUE)
  schema_all$Status <- ifelse(
    is.na(schema_all$Type_Previous), "NEW COLUMN",
    ifelse(is.na(schema_all$Type_Current), "DROPPED COLUMN",
           ifelse(schema_all$Type_Previous != schema_all$Type_Current,
                  "TYPE CHANGED", "Unchanged"))
  )
  schema_changes <- schema_all[schema_all$Status != "Unchanged", ]

  .pivot <- function(df, suffix) {
    checks <- unique(df$dq_check)
    wide   <- data.frame(column_name = unique(df$column_name),
                         stringsAsFactors = FALSE)
    for (chk in checks) {
      sub       <- df[df$dq_check == chk, c("column_name", "value")]
      names(sub)[2] <- paste0(chk, suffix)
      wide <- merge(wide, sub, by = "column_name", all.x = TRUE)
    }
    wide
  }

  wide_prev <- .pivot(stats_prev, "_prev")
  wide_curr <- .pivot(stats_curr, "_curr")
  col_drift  <- merge(wide_prev, wide_curr, by = "column_name", all = TRUE)

  .col <- function(df, nm) {
    if (nm %in% names(df)) .safe_num(df[[nm]])
    else rep(NA_real_, nrow(df))
  }

  dd <- data.frame(Column = col_drift$column_name, stringsAsFactors = FALSE)

  dd$missing_rate_prev      <- .col(col_drift, "missing_rate_prev")
  dd$missing_rate_curr      <- .col(col_drift, "missing_rate_curr")
  dd$missing_rate_change_pp <- (dd$missing_rate_curr - dd$missing_rate_prev) * 100
  dd$missing_rate_exceeds   <- abs(dd$missing_rate_change_pp) >
                               thresholds$max_missing_rate_change_pp

  dd$non_numeric_rate_prev      <- .col(col_drift, "non_numeric_rate_prev")
  dd$non_numeric_rate_curr      <- .col(col_drift, "non_numeric_rate_curr")
  dd$non_numeric_rate_change_pp <- (dd$non_numeric_rate_curr -
                                    dd$non_numeric_rate_prev) * 100
  dd$non_numeric_rate_exceeds   <- !is.na(dd$non_numeric_rate_change_pp) &
    abs(dd$non_numeric_rate_change_pp) > thresholds$max_non_numeric_rate_change_pp

  dd$numeric_mean_prev      <- .col(col_drift, "numeric_parseable_mean_prev")
  dd$numeric_mean_curr      <- .col(col_drift, "numeric_parseable_mean_curr")
  dd$numeric_mean_shift_pct <- ifelse(
    !is.na(dd$numeric_mean_prev) & dd$numeric_mean_prev != 0,
    (dd$numeric_mean_curr - dd$numeric_mean_prev) / abs(dd$numeric_mean_prev),
    NA_real_
  )
  dd$numeric_mean_exceeds   <- !is.na(dd$numeric_mean_shift_pct) &
    abs(dd$numeric_mean_shift_pct) > thresholds$max_numeric_mean_shift_pct

  dd$distinct_count_prev       <- .col(col_drift, "distinct_count_prev")
  dd$distinct_count_curr       <- .col(col_drift, "distinct_count_curr")
  dd$distinct_count_change     <- dd$distinct_count_curr - dd$distinct_count_prev
  dd$distinct_count_change_pct <- ifelse(
    !is.na(dd$distinct_count_prev) & dd$distinct_count_prev != 0,
    dd$distinct_count_change / dd$distinct_count_prev,
    NA_real_
  )

  mr <- dd[!is.na(dd$missing_rate_change_pp) & dd$missing_rate_change_pp != 0, ]
  mr <- mr[order(-abs(mr$missing_rate_change_pp)), ]

  nn <- dd[!is.na(dd$non_numeric_rate_change_pp) &
             dd$non_numeric_rate_change_pp != 0, ]
  nn <- nn[order(-abs(nn$non_numeric_rate_change_pp)), ]

  ms <- dd[!is.na(dd$numeric_mean_shift_pct), ]
  ms <- ms[order(-abs(ms$numeric_mean_shift_pct)), ]

  dc <- dd[!is.na(dd$distinct_count_change) & dd$distinct_count_change != 0, ]
  dc <- dc[order(-abs(dc$distinct_count_change)), ]

  list(
    dataset_name         = dataset_name,
    snap_prev            = snap_prev,
    snap_curr            = snap_curr,
    table_drift          = table_drift,
    schema_changes       = schema_changes,
    missing_rate_changes = mr,
    non_numeric_changes  = nn,
    mean_shifts          = ms,
    distinct_changes     = dc
  )
}

.write_drift_html_report <- function(drift, outfile) {
  template <- system.file("templates", "drift_report.qmd", package = "dqcheckr")
  if (!nzchar(template))
    rlang::abort("Drift report template not found in package installation.",
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))
  if (!quarto::quarto_available()) {
    warning("Quarto CLI not found -- HTML drift report skipped. Install from https://quarto.org",
            call. = FALSE)
    return(invisible(NULL))
  }

  dir.create(dirname(normalizePath(outfile, mustWork = FALSE)),
             showWarnings = FALSE, recursive = TRUE)
  outfile <- normalizePath(outfile, mustWork = FALSE)

  rds_path <- tempfile(fileext = ".rds")
  on.exit(unlink(rds_path), add = TRUE)
  saveRDS(list(drift = drift), rds_path)

  render_dir   <- tempfile()
  dir.create(render_dir, recursive = TRUE)
  on.exit(unlink(render_dir, recursive = TRUE), add = TRUE)
  tmp_template <- file.path(render_dir, "drift_report.qmd")
  file.copy(template, tmp_template)

  quarto::quarto_render(
    input          = tmp_template,
    output_file    = basename(outfile),
    execute_params = list(rds_path = rds_path),
    quiet          = TRUE
  )

  rendered <- file.path(render_dir, basename(outfile))
  if (file.exists(rendered)) file.rename(rendered, outfile)
  invisible(outfile)
}
