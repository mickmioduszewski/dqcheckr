#' Render the HTML data quality report
#' @keywords internal
render_report <- function(dataset_name, file_name, file_path, df,
                          qc_results, cp_results, custom_results,
                          snapshot_history, config, output_dir,
                          open_report = TRUE) {
  template <- system.file("templates", "report.Rmd", package = "dqcheckr")
  if (!nzchar(template)) {
    rlang::abort("Report template not found in package installation.")
  }

  # Normalise to absolute path: rmarkdown changes wd to the template dir,
  # which breaks any relative path supplied as output_file.
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = FALSE)
  file_path  <- normalizePath(file_path,  mustWork = FALSE)

  ts    <- format(Sys.time(), "%Y%m%d_%H%M%S")
  fname <- sprintf("%s_%s.html", dataset_name, ts)
  out   <- file.path(output_dir, fname)

  col_stats <- compute_col_stats(df, config, qc_results)

  rmarkdown::render(
    input       = template,
    output_file = out,
    params      = list(
      dataset_name     = dataset_name,
      file_name        = file_name,
      file_path        = file_path,
      run_timestamp    = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      df               = df,
      qc_results       = qc_results,
      cp_results       = cp_results,
      custom_results   = custom_results,
      snapshot_history = snapshot_history,
      config           = config,
      col_stats        = col_stats,
      overall_status   = overall_status(c(qc_results, cp_results,
                                          custom_results))
    ),
    quiet = TRUE
  )

  if (open_report && interactive()) utils::browseURL(out)

  invisible(out)
}
