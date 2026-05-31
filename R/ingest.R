#' Detect current and previous dataset files
#'
#' Resolves the current and previous file paths from the configuration. If
#' \code{current_file} is set explicitly, it is used directly. Otherwise the
#' two most recently modified files in \code{folder} are used.
#'
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A named list with elements \code{current} (character path) and
#'   \code{previous} (character path or \code{NULL}).
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg <- load_config("starwars_csv", config_dir = cfg_dir)
#' cfg$current_file <- system.file("demonstrations/data/starwars.csv",
#'                                  package = "dqcheckr")
#' files <- detect_files(cfg)
#' files$current
#'
#' @export
detect_files <- function(config) {
  if (!is.null(config$current_file)) {
    if (!file.exists(config$current_file)) {
      rlang::abort(paste0("current_file not found: ", config$current_file))
    }
    previous <- NULL
    if (!is.null(config$previous_file)) {
      if (!file.exists(config$previous_file)) {
        rlang::abort(paste0("previous_file not found: ", config$previous_file))
      }
      previous <- config$previous_file
    }
    return(list(current = config$current_file, previous = previous))
  }

  folder <- config$folder
  if (is.null(folder) || !dir.exists(folder)) {
    rlang::abort(paste0("Folder not found: ", folder %||% "(NULL)"))
  }

  files <- list.files(folder, full.names = TRUE)
  if (length(files) == 0) {
    rlang::abort(paste0("No files found in folder: ", folder))
  }

  mtimes <- file.mtime(files)
  files  <- files[order(mtimes, basename(files), decreasing = TRUE)]
  list(
    current  = files[1],
    previous = if (length(files) >= 2) files[2] else NULL
  )
}

#' Read a dataset file into a data frame or DuckDB table
#'
#' Reads a CSV, fixed-width, or Parquet file. When \code{con} is a DuckDB
#' connection the file is registered as an in-memory DuckDB table named
#' \code{"current_data"} and the table name is returned as a
#' \code{character(1)}. When \code{con = NULL} (the default) a \code{data.frame}
#' is returned as before.
#'
#' @param path Character. Path to the file to read.
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}. Must include \code{format} (\code{"csv"},
#'   \code{"fwf"}, or \code{"parquet"}). For FWF files, \code{fwf_widths} is
#'   required and \code{fwf_col_names} and \code{fwf_skip} are optional.
#' @param con A DuckDB connection (from \code{DBI::dbConnect(duckdb::duckdb())})
#'   or \code{NULL} (default). When provided the file is registered in DuckDB
#'   and the table name is returned.
#' @param tbl_name Character. Name to use for the DuckDB table when \code{con}
#'   is provided. Defaults to \code{"current_data"}.
#'
#' @return When \code{con = NULL}: a \code{data.frame} with all columns as
#'   character vectors. When \code{con} is provided: the value of \code{tbl_name}
#'   (a DuckDB table name).
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#'
#' @export
read_dataset <- function(path, config, con = NULL, tbl_name = "current_data") {
  fmt <- tolower(config$format %||% "csv")
  enc <- config$encoding %||% "UTF-8"

  if (!is.null(con)) {
    if (fmt == "csv") {
      delim <- config$delimiter %||% ","
      col_info <- DBI::dbGetQuery(con, DBI::sqlInterpolate(
        con,
        "SELECT column_name FROM (DESCRIBE SELECT * FROM read_csv_auto(?)) LIMIT 0",
        path))
      col_names <- DBI::dbGetQuery(
        con, DBI::sqlInterpolate(con,
          "SELECT column_name FROM (DESCRIBE SELECT * FROM read_csv_auto(?))",
          path))$column_name
      trim_cols <- paste(
        sprintf("TRIM(CAST(%s AS VARCHAR)) AS %s",
                DBI::dbQuoteIdentifier(con, col_names),
                DBI::dbQuoteIdentifier(con, col_names)),
        collapse = ", ")
      DBI::dbExecute(con, sprintf(
        "CREATE OR REPLACE TABLE %s AS SELECT %s FROM read_csv_auto(%s, delim=%s, all_varchar=true)",
        DBI::dbQuoteIdentifier(con, tbl_name),
        trim_cols,
        DBI::dbQuoteLiteral(con, path),
        DBI::dbQuoteLiteral(con, delim)))
      return(tbl_name)
    } else if (fmt == "fwf") {
      if (is.null(config$fwf_widths))
        rlang::abort("fwf_widths must be set in config for fixed-width files")
      df_fwf <- tryCatch(
        as.data.frame(readr::read_fwf(
          path,
          col_positions = readr::fwf_widths(config$fwf_widths,
                                            col_names = config$fwf_col_names),
          col_types  = readr::cols(.default = "c"),
          locale     = readr::locale(encoding = enc),
          skip       = config$fwf_skip %||% 0L,
          show_col_types = FALSE
        ), stringsAsFactors = FALSE),
        error = function(e) rlang::abort(paste0("Failed to parse file '", path, "': ", conditionMessage(e)))
      )
      for (col in names(df_fwf)) df_fwf[[col]] <- trimws(df_fwf[[col]])
      DBI::dbWriteTable(con, tbl_name, df_fwf, overwrite = TRUE)
      return(tbl_name)
    } else if (fmt == "parquet") {
      DBI::dbExecute(con, sprintf(
        "CREATE OR REPLACE TABLE %s AS SELECT * FROM read_parquet(%s)",
        DBI::dbQuoteIdentifier(con, tbl_name),
        DBI::dbQuoteLiteral(con, path)))
      return(tbl_name)
    } else {
      rlang::abort(paste0("Unsupported format: '", fmt, "'. Must be 'csv', 'fwf', or 'parquet'."))
    }
  }

  if (fmt == "csv") {
    delim <- config$delimiter %||% ","
    df <- tryCatch(
      readr::read_delim(
        path,
        delim      = delim,
        col_types  = readr::cols(.default = "c"),
        locale     = readr::locale(encoding = enc),
        show_col_types = FALSE
      ),
      error = function(e) rlang::abort(paste0("Failed to parse file '", path, "': ", conditionMessage(e)))
    )
  } else if (fmt == "fwf") {
    if (is.null(config$fwf_widths)) {
      rlang::abort("fwf_widths must be set in config for fixed-width files")
    }
    df <- tryCatch(
      readr::read_fwf(
        path,
        col_positions = readr::fwf_widths(
          config$fwf_widths,
          col_names = config$fwf_col_names
        ),
        col_types  = readr::cols(.default = "c"),
        locale     = readr::locale(encoding = enc),
        skip       = config$fwf_skip %||% 0L,
        show_col_types = FALSE
      ),
      error = function(e) rlang::abort(paste0("Failed to parse file '", path, "': ", conditionMessage(e)))
    )
  } else {
    rlang::abort(paste0("Unsupported format: '", fmt, "'. Must be 'csv', 'fwf', or 'parquet'."))
  }

  df <- as.data.frame(df, stringsAsFactors = FALSE)
  for (col in names(df)) {
    df[[col]] <- trimws(df[[col]])
  }
  df
}
