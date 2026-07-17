#' Run a full data quality check pipeline
#'
#' Orchestrates the complete dqcheckr pipeline: loads configuration, detects
#' files, runs QC and comparison checks, writes a snapshot to SQLite, and
#' renders an HTML report.
#'
#' @param dataset_name Character. Name of the dataset; must match a YAML config
#'   file \code{<dataset_name>.yml} in \code{config_dir}.
#' @param config_dir Character. Path to the directory containing
#'   \code{dqcheckr.yml} and the dataset YAML file. Defaults to \code{"."}.
#' @param open_report Logical. Whether to open the HTML report in the browser
#'   after rendering (only takes effect in interactive sessions).
#'
#' @note Relative \code{snapshot_db} and \code{report_output_dir} config
#'   values resolve against the R process's \emph{working directory}, not
#'   against \code{config_dir}. Run from the deployment root (the directory
#'   containing \code{config/}, \code{data/}, \code{reports/}) or use
#'   absolute paths in the config; otherwise a fresh snapshot database is
#'   silently created wherever the process happens to be running.
#'
#' @return Invisibly, a named list with:
#'   \describe{
#'     \item{status}{Overall status string: \code{"PASS"}, \code{"WARN"},
#'       \code{"FAIL"}, or \code{"INFO"}.}
#'     \item{report_path}{Absolute path to the rendered HTML report, or
#'       \code{NULL} if rendering was skipped.}
#'     \item{snapshot_id}{Integer row ID of the snapshot written to SQLite,
#'       or \code{NULL} if the write failed.}
#'   }
#'
#' @examples
#' \donttest{
#' tmp <- gsub("\\\\", "/", tempdir())
#' dat <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' writeLines(c(
#'   paste0('snapshot_db: "',       tmp, '/snap.sqlite"'),
#'   paste0('report_output_dir: "', tmp, '"'),
#'   'default_rules:',
#'   '  max_missing_rate: 0.60',
#'   '  min_row_count: 80'
#' ), file.path(tmp, "dqcheckr.yml"))
#' writeLines(c(
#'   'dataset_name: "starwars_csv"',
#'   paste0('current_file: "', dat, '"'),
#'   'format: csv',
#'   'encoding: "UTF-8"',
#'   'delimiter: ","'
#' ), file.path(tmp, "starwars_csv.yml"))
#' result <- run_dq_check("starwars_csv", config_dir = tmp, open_report = FALSE)
#' result$status
#' }
#'
#' @export
run_dq_check <- function(dataset_name,
                         config_dir   = ".",
                         open_report  = TRUE) {
  config <- load_config(dataset_name, config_dir)

  # Single clock read for the whole run: the snapshot's run_timestamp and the
  # report filename must come from the same instant, because consumers (the
  # GUI's history links) reconstruct the report filename from the stored
  # timestamp.
  run_time <- Sys.time()

  files   <- detect_files(config)
  df_curr <- read_dataset(files$current, config)
  df_prev <- if (!is.null(files$previous))
    read_dataset(files$previous, config)
  else
    NULL

  # Resolve column types once; every type-dependent check shares this map.
  types_curr <- resolve_col_types(df_curr, config)

  qc_results     <- run_qc_checks(df_curr, config, file_path = files$current,
                                  types = types_curr)
  cp_results     <- if (!is.null(df_prev))
    run_comparison_checks(df_curr, df_prev, config, types_current = types_curr)
  else
    list()
  custom_results <- run_custom_checks(df_curr, config)

  col_stats <- compute_col_stats(df_curr, config, types = types_curr)

  db_path         <- normalizePath(config$snapshot_db %||% "data/snapshots.sqlite",
                                   mustWork = FALSE)
  comparison_mode <- if (!is.null(df_prev)) "comparison" else "single"
  snapshot_id     <- write_snapshot(
    db_path, dataset_name,
    basename(files$current),
    df_curr, qc_results, cp_results, custom_results, config,
    col_stats       = col_stats,
    comparison_mode = comparison_mode,
    run_time        = run_time,
    report_file     = report_filename(dataset_name, run_time)
  )

  snapshot_history <- read_recent_snapshots(db_path, dataset_name, n = 10)

  report_path <- tryCatch(
    render_report(
      dataset_name     = dataset_name,
      file_name        = basename(files$current),
      file_path        = files$current,
      df               = df_curr,
      qc_results       = qc_results,
      cp_results       = cp_results,
      custom_results   = custom_results,
      snapshot_history = snapshot_history,
      config           = config,
      col_stats        = col_stats,
      output_dir       = config$report_output_dir %||% "reports/",
      open_report      = open_report,
      run_time         = run_time
    ),
    error = function(e) {
      warning("Report rendering failed. Original error: ", conditionMessage(e),
              call. = FALSE)
      invisible(NULL)
    }
  )

  # The report is the run's second artefact. render_report() returns NULL both
  # when it threw (handled above) and when it was skipped because the Quarto CLI
  # is absent -- in either case no file was written, so the snapshot must not
  # keep the INSERT-time render_status = 'success' and its optimistic
  # report_file. Reconcile against what actually happened rather than only on
  # the error path. (When snapshot_id is NULL the write itself failed and there
  # is no row to mark -- the earlier warning already covers that.)
  if (is.null(report_path) && !is.null(snapshot_id))
    .mark_render_failed(db_path, snapshot_id)

  status <- overall_status(c(qc_results, cp_results, custom_results))
  all_r  <- c(qc_results, cp_results, custom_results)
  n_warn <- sum(vapply(all_r, \(r) r$status == "WARN", logical(1)))
  n_fail <- sum(vapply(all_r, \(r) r$status == "FAIL", logical(1)))

  report_label <- if (!is.null(report_path)) report_path else "(renderer not available)"
  # write_snapshot() is non-fatal: on failure it warns and returns NULL. Say so
  # on the result line rather than printing an unqualified success, or the run
  # reads as fully recorded when its history row was actually lost.
  snapshot_note <- if (is.null(snapshot_id)) " [snapshot NOT recorded]" else ""
  message(sprintf("[dqcheckr] %s: %s - %d warning(s), %d failure(s). Report: %s%s",
                  dataset_name, status, n_warn, n_fail, report_label, snapshot_note))

  invisible(list(
    status      = status,
    report_path = report_path,
    snapshot_id = snapshot_id
  ))
}
