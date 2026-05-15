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
#' @return Invisibly, a named list with:
#'   \describe{
#'     \item{status}{Overall status string: \code{"PASS"}, \code{"WARN"},
#'       \code{"FAIL"}, or \code{"INFO"}.}
#'     \item{report_path}{Absolute path to the rendered HTML report.}
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

  files   <- detect_files(config)
  df_curr <- read_dataset(files$current, config)
  df_prev <- if (!is.null(files$previous))
    read_dataset(files$previous, config)
  else
    NULL

  qc_results     <- run_qc_checks(df_curr, config)
  cp_results     <- if (!is.null(df_prev))
    run_comparison_checks(df_curr, df_prev, config)
  else
    list()
  custom_results <- run_custom_checks(df_curr, config)

  col_stats <- compute_col_stats(df_curr, config, qc_results)

  db_path     <- normalizePath(config$snapshot_db %||% "data/snapshots.sqlite",
                               mustWork = FALSE)
  snapshot_id <- write_snapshot(
    db_path, dataset_name,
    basename(files$current),
    df_curr, qc_results, cp_results, custom_results, config,
    col_stats = col_stats
  )

  snapshot_history <- read_recent_snapshots(db_path, dataset_name, n = 10)

  report_path <- render_report(
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
    open_report      = open_report
  )

  status <- overall_status(c(qc_results, cp_results, custom_results))
  all_r  <- c(qc_results, cp_results, custom_results)
  n_warn <- sum(vapply(all_r, \(r) r$status == "WARN", logical(1)))
  n_fail <- sum(vapply(all_r, \(r) r$status == "FAIL", logical(1)))

  message(sprintf("[dqcheckr] %s: %s - %d warning(s), %d failure(s). Report: %s",
                  dataset_name, status, n_warn, n_fail, report_path))

  invisible(list(
    status      = status,
    report_path = report_path,
    snapshot_id = snapshot_id
  ))
}
