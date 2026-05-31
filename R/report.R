# Quarto's execute_params rejects NA values; replace NAs with "" so the
# template's existing is.na() / == "" checks still display "-" correctly.
.sanitize_results <- function(results) {
  lapply(results, function(r) {
    r$column    <- if (is.na(r$column))    "" else r$column
    r$threshold <- if (is.na(r$threshold)) "" else r$threshold
    r
  })
}

.sanitize_df <- function(df) {
  if (is.null(df) || !is.data.frame(df) || nrow(df) == 0) return(df)
  for (col in names(df)) {
    v <- df[[col]]
    if (is.character(v))  df[[col]][is.na(v)] <- ""
    else if (is.numeric(v))  df[[col]][is.na(v)] <- 0
    else if (is.logical(v))  df[[col]][is.na(v)] <- FALSE
  }
  df
}

# Recursively replace NA values so that quarto::quarto_render() execute_params
# validation passes. Quarto rejects NA in character vectors but allows NA_real_.
.sanitize_params <- function(x) {
  if (is.data.frame(x)) return(.sanitize_df(x))
  if (is.list(x))       return(lapply(x, .sanitize_params))
  if (is.character(x))  return(ifelse(is.na(x), "", x))
  x
}

#' Render the HTML data quality report
#' @keywords internal
#' @noRd
render_report <- function(dataset_name, file_name, file_path, df,
                          qc_results, cp_results, custom_results,
                          snapshot_history, config, col_stats = NULL, output_dir,
                          open_report = TRUE) {
  template <- system.file("templates", "report.qmd", package = "dqcheckr")
  if (!nzchar(template)) {
    rlang::abort("Report template not found in package installation.")
  }

  if (!quarto::quarto_available()) {
    warning("Quarto CLI not found -- HTML report skipped. Install from https://quarto.org",
            call. = FALSE)
    return(invisible(NULL))
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = FALSE)
  file_path  <- normalizePath(file_path,  mustWork = FALSE)

  ts    <- format(Sys.time(), "%Y%m%d_%H%M%S")
  fname <- sprintf("%s_%s.html", dataset_name, ts)
  out   <- file.path(output_dir, fname)

  if (is.null(col_stats)) col_stats <- compute_col_stats(df, config)

  # quarto execute_params only supports YAML-serialisable scalars.
  # Save the complex R objects (data frames, result lists) to an .rds file
  # and pass only the path as a param; the template reads from there.
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

  # Render from a temp copy so the installed template directory stays clean
  render_dir  <- tempfile()
  dir.create(render_dir, recursive = TRUE)
  on.exit(unlink(render_dir, recursive = TRUE), add = TRUE)
  tmp_template <- file.path(render_dir, "report.qmd")
  file.copy(template, tmp_template)

  quarto::quarto_render(
    input          = tmp_template,
    output_file    = basename(out),
    execute_params = list(rds_path = rds_path),
    quiet = TRUE
  )

  rendered <- file.path(render_dir, basename(out))
  if (file.exists(rendered)) {
    file.rename(rendered, out)
  }

  if (open_report && interactive()) utils::browseURL(out)

  invisible(out)
}
