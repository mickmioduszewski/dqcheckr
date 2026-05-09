#' Null-coalescing operator
#' @keywords internal
#' @noRd
`%||%` <- function(a, b) if (!is.null(a)) a else b

#' Construct a data quality result object
#'
#' Creates the atomic result unit returned by every check function.
#'
#' @param check_id Character. Short identifier for the check (e.g. \code{"QC-01"}).
#' @param check_name Character. Human-readable name of the check.
#' @param column Character. Column the check applies to, or \code{NA_character_}
#'   for row-level or file-level checks.
#' @param status Character. One of \code{"PASS"}, \code{"WARN"}, \code{"FAIL"},
#'   or \code{"INFO"}.
#' @param observed Character. What was observed (e.g. \code{"5.2\% missing"}).
#' @param threshold Character. The configured threshold, or \code{NA_character_}
#'   if not applicable.
#' @param message Character. Human-readable description of the result.
#'
#' @return A named list with seven elements: \code{check_id}, \code{check_name},
#'   \code{column}, \code{status}, \code{observed}, \code{threshold},
#'   \code{message}.
#'
#' @examples
#' dq_result("QC-01", "Missing rate", column = "age",
#'           status = "PASS", observed = "0% missing",
#'           message = "No missing values.")
#'
#' @export
dq_result <- function(check_id, check_name, column = NA_character_,
                      status, observed, threshold = NA_character_, message) {
  valid_statuses <- c("PASS", "WARN", "FAIL", "INFO")
  if (is.null(status) || !status %in% valid_statuses) {
    rlang::abort(sprintf("status must be one of: %s (got: %s)",
                         paste(valid_statuses, collapse = ", "), status),
                 .internal = FALSE)
  }
  list(
    check_id   = check_id,
    check_name = check_name,
    column     = column,
    status     = status,
    observed   = as.character(observed),
    threshold  = if (is.na(threshold)) NA_character_ else as.character(threshold),
    message    = as.character(message)
  )
}

#' Load and merge dataset configuration
#'
#' Reads the global \code{dqcheckr.yml} and the dataset-specific YAML, merging
#' \code{rule_overrides} from the dataset config on top of \code{default_rules}
#' from the global config.
#'
#' @param dataset_name Character. Dataset name; must match
#'   \code{<dataset_name>.yml} in \code{config_dir}.
#' @param config_dir Character. Path to the directory containing both YAML
#'   files.
#'
#' @return A named list representing the merged configuration.
#'
#' @examples
#' \dontrun{
#' cfg <- load_config("my_dataset", config_dir = "config")
#' cfg$format
#' }
#'
#' @export
load_config <- function(dataset_name, config_dir) {
  global_path  <- file.path(config_dir, "dqcheckr.yml")
  dataset_path <- file.path(config_dir, paste0(dataset_name, ".yml"))

  if (!file.exists(global_path)) {
    rlang::abort(paste0("Global config not found: ", global_path))
  }
  if (!file.exists(dataset_path)) {
    rlang::abort(paste0("Dataset config not found: ", dataset_path))
  }

  global_cfg  <- yaml::read_yaml(global_path)
  dataset_cfg <- yaml::read_yaml(dataset_path)

  rules <- global_cfg$default_rules %||% list()

  if (!is.null(dataset_cfg$rule_overrides)) {
    for (key in names(dataset_cfg$rule_overrides)) {
      rules[[key]] <- dataset_cfg$rule_overrides[[key]]
    }
  }

  dataset_cfg$rules <- rules
  dataset_cfg
}

#' Infer the logical type of a character column
#' @keywords internal
infer_col_type <- function(x) {
  non_empty <- x[!is.na(x) & x != ""]

  if (length(non_empty) == 0) return("unknown")

  date_formats <- c("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%Y%m%d", "%d-%m-%Y")
  for (fmt in date_formats) {
    parsed <- suppressWarnings(as.Date(non_empty, format = fmt))
    if (!any(is.na(parsed))) return("date")
  }

  numeric_vals <- suppressWarnings(as.numeric(non_empty))
  if (mean(!is.na(numeric_vals)) >= 0.90) return("numeric")

  "character"
}

#' Compute the worst status across a list of dq_result objects
#' @keywords internal
overall_status <- function(results) {
  if (length(results) == 0) return("INFO")
  statuses <- vapply(results, `[[`, character(1), "status")
  if ("FAIL" %in% statuses) return("FAIL")
  if ("WARN" %in% statuses) return("WARN")
  if ("PASS" %in% statuses) return("PASS")
  "INFO"
}
