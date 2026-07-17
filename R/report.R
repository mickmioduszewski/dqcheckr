#' Render the HTML data quality report
#' @keywords internal
#' @noRd
render_report <- function(dataset_name, file_name, file_path, df,
                          qc_results, cp_results, custom_results,
                          snapshot_history, config, col_stats = NULL, output_dir,
                          open_report = TRUE, run_time = NULL,
                          snapshot_id = NULL) {
  # run_time is the run's single timestamp (see run_dq_check) so the filename
  # slug matches the snapshot's run_timestamp exactly; snapshot_id is appended
  # to keep two same-second runs of one dataset from colliding on one file.
  run_time <- run_time %||% Sys.time()
  if (!quarto::quarto_available()) {
    warning("Quarto CLI not found -- HTML report skipped. Install from https://quarto.org",
            call. = FALSE)
    return(invisible(NULL))
  }

  template <- system.file("templates", "report.qmd", package = "dqcheckr")
  if (!nzchar(template))
    rlang::abort("Report template not found in package installation.",
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = FALSE)
  file_path  <- normalizePath(file_path,  mustWork = FALSE)

  fname <- report_filename(dataset_name, run_time, snapshot_id)
  out   <- file.path(output_dir, fname)

  if (is.null(col_stats)) col_stats <- compute_col_stats(df, config)

  # Serialize all R objects to RDS so Quarto YAML params carry only scalar paths.
  # (Quarto cannot round-trip R NA values through YAML.)
  rds_path <- tempfile(fileext = ".rds")
  on.exit(unlink(rds_path), add = TRUE)
  saveRDS(list(
    dataset_name     = dataset_name,
    file_name        = file_name,
    file_path        = file_path,
    # Intentionally local time (tz = "") -- this is the "Run time" shown to
    # the user in the report (report.qmd:71), unlike the UTC timestamps used
    # for filename slugs and snapshot DB keys elsewhere in this file.
    run_timestamp    = format(run_time, "%Y-%m-%d %H:%M:%S", tz = ""),
    df               = df,
    qc_results       = qc_results,
    cp_results       = cp_results,
    custom_results   = custom_results,
    snapshot_history = snapshot_history,
    config           = config,
    col_stats        = col_stats,
    overall_status   = overall_status(c(qc_results, cp_results, custom_results))
  ), rds_path)

  render_dir   <- tempfile()
  dir.create(render_dir, recursive = TRUE)
  on.exit(unlink(render_dir, recursive = TRUE), add = TRUE)
  tmp_template <- file.path(render_dir, "report.qmd")
  file.copy(template, tmp_template)

  quarto::quarto_render(
    input          = tmp_template,
    output_file    = fname,
    execute_params = list(rds_path = rds_path),
    quiet          = TRUE
  )

  rendered <- file.path(render_dir, fname)
  if (!file.exists(rendered))
    # Quarto returned without raising but left no file (e.g. a template that
    # produced no output). Returning `out` here would name a report that does
    # not exist and let run_dq_check() record the run as a success.
    rlang::abort(
      paste0("Quarto rendering produced no output file for '", fname, "'."),
      class = c("dqcheckr_render_error", "dqcheckr_error"))
  .move_file(rendered, out)

  if (open_report && interactive()) utils::browseURL(out)

  invisible(out)
}
