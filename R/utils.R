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
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg <- load_config("starwars_csv", config_dir = cfg_dir)
#' cfg$format
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

  # Propagate top-level global keys that the dataset config does not override
  for (key in c("snapshot_db", "report_output_dir")) {
    if (is.null(dataset_cfg[[key]]) && !is.null(global_cfg[[key]]))
      dataset_cfg[[key]] <- global_cfg[[key]]
  }

  rules <- global_cfg$default_rules %||% list()

  if (!is.null(dataset_cfg$rule_overrides)) {
    for (key in names(dataset_cfg$rule_overrides)) {
      rules[[key]] <- dataset_cfg$rule_overrides[[key]]
    }
  }

  dataset_cfg$rules <- rules

  ct <- dataset_cfg$column_types %||% list()
  if (length(ct) > 0) {
    valid_types <- c("character", "numeric", "date")
    bad <- setdiff(unlist(ct, use.names = FALSE), valid_types)
    if (length(bad) > 0)
      rlang::abort(sprintf(
        "Invalid column_types value(s): %s. Must be one of: %s",
        paste(bad, collapse = ", "), paste(valid_types, collapse = ", ")
      ))
  }

  dataset_cfg
}

#' Infer the logical type of a character column
#'
#' Classifies a character vector as \code{"date"}, \code{"numeric"},
#' \code{"character"}, or \code{"unknown"} by applying rules in priority order.
#'
#' @param x Character vector to classify (as read from a CSV or FWF file).
#' @param threshold Numeric. Minimum proportion of non-empty values that must
#'   parse as numeric for the column to be classified as \code{"numeric"}.
#'   Defaults to \code{0.90}. Configurable via \code{type_inference_threshold}
#'   in \code{rule_overrides}.
#'
#' @return A single character string: \code{"date"}, \code{"numeric"},
#'   \code{"character"}, or \code{"unknown"}.
#'
#' @examples
#' infer_col_type(c("2024-01-01", "2024-06-15"))   # "date"
#' infer_col_type(c("1.5", "2.0", "3.1"))          # "numeric"
#' infer_col_type(c("high", "low", "medium"))       # "character"
#' infer_col_type(c(NA, "", NA))                    # "unknown"
#' infer_col_type(c(rep("1", 17), "a", "b", "c"), threshold = 0.80)  # "numeric"
#'
#' @export
infer_col_type <- function(x, threshold = 0.90) {
  non_empty <- x[!is.na(x) & x != ""]

  if (length(non_empty) == 0) return("unknown")

  date_formats <- c("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%Y%m%d", "%d-%m-%Y")
  for (fmt in date_formats) {
    parsed <- suppressWarnings(as.Date(non_empty, format = fmt))
    if (!any(is.na(parsed))) return("date")
  }

  numeric_vals <- suppressWarnings(as.numeric(non_empty))
  if (mean(!is.na(numeric_vals)) >= threshold) return("numeric")

  "character"
}

#' Resolve the effective type of a column, respecting config overrides
#'
#' Returns the type for \code{col} from the \code{column_types} map in
#' \code{config} if one is set, otherwise falls back to
#' \code{\link{infer_col_type}}. Use this in custom check scripts instead of
#' calling \code{infer_col_type()} directly so that type overrides are
#' respected.
#'
#' @param col Character. Column name.
#' @param x Character vector. The column's values (as read from the file).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A single character string: \code{"date"}, \code{"numeric"},
#'   \code{"character"}, or \code{"unknown"}.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg <- load_config("starwars_csv", config_dir = cfg_dir)
#' resolve_col_type("name", c("Luke", "Leia", "Han"), cfg)   # "character"
#'
#' @export
resolve_col_type <- function(col, x, config) {
  override <- (config$column_types %||% list())[[col]]
  if (!is.null(override)) return(override)
  infer_col_type(x, config$rules$type_inference_threshold %||% 0.90)
}

#' Cap a value vector to at most n entries for display
#'
#' @param vals Character vector of values to display.
#' @param n Maximum number of values to show before truncating.
#' @return A single character string.
#' @keywords internal
#' @noRd
.cap_values <- function(vals, n = 20) {
  if (length(vals) <= n) return(paste(vals, collapse = ", "))
  paste0(paste(vals[seq_len(n)], collapse = ", "),
         " ... and ", length(vals) - n, " more")
}

#' Look up a table-level threshold from config
#'
#' Reads \code{config$rules[[key]]}, falling back to \code{default}.
#'
#' @param config Named list. Merged configuration.
#' @param key Character. Threshold key (e.g. \code{"min_row_count"}).
#' @param default Default value if not found.
#'
#' @return The resolved threshold value.
#' @keywords internal
#' @noRd
table_threshold <- function(config, key, default = NULL) {
  val <- config$rules[[key]]
  if (!is.null(val)) return(val)
  default
}

#' Look up the effective threshold for a check, with per-column fallback
#'
#' Resolution order: \code{column_rules.<col>.<key>} >
#' \code{rules.<key>} > \code{default}.
#'
#' @param config Named list. Merged configuration.
#' @param col Character. Column name.
#' @param key Character. Threshold key (e.g. \code{"max_missing_rate"}).
#' @param default Default value if not found at any level.
#'
#' @return The resolved threshold value.
#' @keywords internal
col_threshold <- function(config, col, key, default = NULL) {
  col_val <- (config$column_rules %||% list())[[col]][[key]]
  if (!is.null(col_val)) return(col_val)
  rule_val <- config$rules[[key]]
  if (!is.null(rule_val)) return(rule_val)
  default
}

#' Compute the worst status across a list of dq_result objects
#'
#' Returns the single worst status in precedence order:
#' \code{"FAIL"} > \code{"WARN"} > \code{"PASS"} > \code{"INFO"}.
#'
#' @param results A list of \code{\link{dq_result}} objects.
#'
#' @return A single character string: \code{"FAIL"}, \code{"WARN"},
#'   \code{"PASS"}, or \code{"INFO"}.
#'
#' @examples
#' r1 <- dq_result("QC-01", "test", status = "PASS", observed = "ok", message = "ok")
#' r2 <- dq_result("QC-02", "test", status = "WARN", observed = "ok", message = "ok")
#' overall_status(list(r1, r2))  # "WARN"
#'
#' @export
overall_status <- function(results) {
  if (length(results) == 0) return("INFO")
  statuses <- vapply(results, `[[`, character(1), "status")
  if ("FAIL" %in% statuses) return("FAIL")
  if ("WARN" %in% statuses) return("WARN")
  if ("PASS" %in% statuses) return("PASS")
  "INFO"
}
