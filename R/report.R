#' Render the HTML data quality report
#' @keywords internal
#' @noRd
render_report <- function(dataset_name, file_name, file_path, df,
                          qc_results, cp_results, custom_results,
                          snapshot_history, config, col_stats = NULL, output_dir,
                          open_report = TRUE) {
  if (!quarto::quarto_available()) {
    warning("Quarto CLI not found — HTML report skipped. Install from https://quarto.org",
            call. = FALSE)
    return(invisible(NULL))
  }

  template <- system.file("templates", "report.qmd", package = "dqcheckr")
  if (!nzchar(template))
    rlang::abort("Report template not found in package installation.")

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = FALSE)
  file_path  <- normalizePath(file_path,  mustWork = FALSE)

  ts    <- format(Sys.time(), "%Y%m%d_%H%M%S")
  fname <- sprintf("%s_%s.html", dataset_name, ts)
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
    run_timestamp    = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
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
  if (file.exists(rendered)) file.rename(rendered, out)

  if (open_report && interactive()) utils::browseURL(out)

  invisible(out)
}
