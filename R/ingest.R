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

  files <- files[order(file.mtime(files), basename(files), decreasing = TRUE)]
  list(
    current  = files[1],
    previous = if (length(files) >= 2) files[2] else NULL
  )
}

#' Read a dataset file into a data frame
#'
#' Reads a CSV or fixed-width file, coercing all columns to character and
#' trimming whitespace. Encoding and delimiter are taken from \code{config}.
#'
#' @param path Character. Path to the file to read.
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}. Must include \code{format} (\code{"csv"} or
#'   \code{"fwf"}). For FWF files, \code{fwf_widths} is required and
#'   \code{fwf_col_names} and \code{fwf_skip} are optional.
#'
#' @return A data frame with all columns as character vectors.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#'
#' @export
read_dataset <- function(path, config) {
  fmt <- tolower(config$format %||% "csv")
  enc <- config$encoding %||% "UTF-8"

  if (fmt == "csv") {
    delim <- config$delimiter %||% ","
    df <- tryCatch(
      readr::read_delim(
        path,
        delim      = delim,
        col_names  = config$col_names  %||% TRUE,
        quote      = config$quote_char %||% '"',
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
    rlang::abort(paste0("Unsupported format: '", config$format, "'. Must be 'csv' or 'fwf'."))
  }

  df <- as.data.frame(df, stringsAsFactors = FALSE)
  for (col in names(df)) {
    df[[col]] <- trimws(df[[col]])
  }
  df
}
