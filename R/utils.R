#' Null-coalescing operator
#' @keywords internal
#' @noRd
`%||%` <- function(a, b) if (!is.null(a)) a else b

#' Test for missing or empty values
#'
#' The single source of the missingness predicate: a value is "missing" when it
#' is \code{NA} or the empty string \code{""}. Shared by the QC checks
#' (\code{checks_generic.R}), the comparison checks (\code{compare.R}), and the
#' snapshot writer (\code{snapshot.R}) so "missing" cannot drift between them.
#' @keywords internal
#' @noRd
.missing_vals <- function(x) is.na(x) | x == ""

#' Drop NULL elements from a list
#'
#' The per-column check loops build their results with \code{lapply()} returning
#' \code{NULL} for skipped columns (numeric-only checks, rule-configured columns,
#' ...), then compact. This keeps accumulation O(n) instead of the O(n^2) that
#' repeated \code{c(results, list(...))} inside a \code{for} loop incurs on wide
#' (100+ column) deliveries.
#' @keywords internal
#' @noRd
.compact <- function(x) x[!vapply(x, is.null, logical(1))]

#' Default thresholds for the version-comparison (CP) checks
#'
#' Single source of the four comparison defaults, read via \code{%||%} by both
#' the CP checks (\code{compare.R}) and the drift report
#' (\code{drift.R}). Keeping them in one place stops the QC/comparison report and
#' the drift report from silently applying different thresholds to the same rule.
#' @keywords internal
#' @noRd
.default_comparison_rules <- list(
  max_row_count_change_pct       = 0.10,
  max_missing_rate_change_pp     = 2.0,
  max_numeric_mean_shift_pct     = 0.20,
  max_non_numeric_rate_change_pp = 1.0
)

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
  if (is.null(status) || length(status) != 1 || !status %in% valid_statuses) {
    rlang::abort(sprintf("status must be one of: %s (got: %s)",
                         paste(valid_statuses, collapse = ", "),
                         paste(deparse(status), collapse = "")),
                 class = c("dqcheckr_invalid_argument", "dqcheckr_error"),
                 .internal = FALSE)
  }
  list(
    check_id   = check_id,
    check_name = check_name,
    column     = column,
    status     = status,
    observed   = as.character(observed),
    threshold  = if (is.null(threshold) || length(threshold) != 1 || is.na(threshold))
      NA_character_ else as.character(threshold),
    message    = as.character(message)
  )
}

#' Load and merge dataset configuration
#'
#' Reads the global \code{dqcheckr.yml} and the dataset-specific YAML, merging
#' \code{rule_overrides} from the dataset config on top of \code{default_rules}
#' from the global config. Top-level keys \code{snapshot_db} and
#' \code{report_output_dir} are inherited from the global config when absent
#' from the dataset config.
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

  if (!file.exists(global_path))
    rlang::abort(paste0("Global config not found: ", global_path),
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))
  if (!file.exists(dataset_path))
    rlang::abort(paste0("Dataset config not found: ", dataset_path),
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))

  global_cfg  <- yaml::read_yaml(global_path)
  dataset_cfg <- yaml::read_yaml(dataset_path)

  for (key in c("snapshot_db", "report_output_dir")) {
    if (is.null(dataset_cfg[[key]]) && !is.null(global_cfg[[key]]))
      dataset_cfg[[key]] <- global_cfg[[key]]
  }

  rules <- global_cfg[["default_rules"]] %||% list()
  if (!is.null(dataset_cfg[["rule_overrides"]])) {
    for (key in names(dataset_cfg[["rule_overrides"]]))
      rules[[key]] <- dataset_cfg[["rule_overrides"]][[key]]
  }
  dataset_cfg[["rules"]] <- rules

  ct <- dataset_cfg[["column_types"]] %||% list()
  if (length(ct) > 0) {
    valid_types <- c("character", "numeric", "date")
    bad <- setdiff(unlist(ct, use.names = FALSE), valid_types)
    if (length(bad) > 0)
      rlang::abort(sprintf(
        "Invalid column_types value(s): %s. Must be one of: %s",
        paste(bad, collapse = ", "), paste(valid_types, collapse = ", ")
      ), class = c("dqcheckr_invalid_config", "dqcheckr_error"))
  }

  # column_order_severity flows straight into a dq_result status (CP-08), so
  # a typo like "error" would otherwise abort the run mid-check.
  sev <- dataset_cfg[["rules"]][["column_order_severity"]]
  if (!is.null(sev) &&
      !(length(sev) == 1 && tolower(sev) %in% c("pass", "warn", "fail", "info")))
    rlang::abort(sprintf(
      "Invalid column_order_severity value: %s. Must be one of: pass, warn, fail, info",
      paste(deparse(sev), collapse = "")
    ), class = c("dqcheckr_invalid_config", "dqcheckr_error"))

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
#' @details
#' Date formats are tried in this fixed precedence order:
#' \code{"\%Y-\%m-\%d"}, \code{"\%d/\%m/\%Y"}, \code{"\%m/\%d/\%Y"},
#' \code{"\%Y\%m\%d"}, \code{"\%d-\%m-\%Y"}. A column is classified as
#' \code{"date"} only when \emph{every} non-empty value both matches that
#' format's exact character shape and parses as a valid calendar date; a single
#' malformed date therefore flips the whole column to \code{"numeric"} or
#' \code{"character"} (such flips between deliveries are surfaced by check
#' CP-02c). The shape is anchored, so a value with trailing characters
#' (\code{"2024-01-15x"}) or extra digits (the 9-digit \code{"202401159"}) is
#' \emph{not} treated as a date. Two caveats follow from the precedence rules:
#' ambiguous day/month values resolve day-first (\code{"\%d/\%m/\%Y"} is
#' tried before \code{"\%m/\%d/\%Y"}), and all-8-digit identifier columns
#' whose values happen to be valid \code{"\%Y\%m\%d"} dates classify as dates.
#' Pin the type with an entry in the \code{column_types} config map when the
#' heuristic gets a column wrong.
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

  # Each format is paired with an anchored shape regex. as.Date() delegates to
  # strptime(), which matches a *prefix* and silently ignores trailing
  # characters — so "2024-01-15xyz" and the 9-digit id "202401159" (its first 8
  # chars parse under %Y%m%d) would both be accepted as dates. Requiring the
  # whole string to match the format's shape first closes that. The %Y%m%d shape
  # is exactly 8 digits, so a genuine 8-digit identifier that also happens to be
  # a valid calendar date still classifies as "date" (documented caveat below),
  # while a 9-digit id is now correctly rejected.
  #
  # Cheap rejection: a format whose shape or parse fails anywhere in the first
  # 100 values cannot pass the all-must-match rule, so skip the full-column pass
  # for it. Results are identical; only non-matching formats get cheaper.
  head_sample  <- non_empty[seq_len(min(100L, length(non_empty)))]
  date_formats <- c("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%Y%m%d", "%d-%m-%Y")
  date_shapes  <- c("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", "^[0-9]{2}/[0-9]{2}/[0-9]{4}$",
                    "^[0-9]{2}/[0-9]{2}/[0-9]{4}$", "^[0-9]{8}$",
                    "^[0-9]{2}-[0-9]{2}-[0-9]{4}$")
  for (i in seq_along(date_formats)) {
    fmt   <- date_formats[[i]]
    shape <- date_shapes[[i]]
    if (!all(grepl(shape, head_sample))) next
    parsed_head <- suppressWarnings(as.Date(head_sample, format = fmt))
    if (any(is.na(parsed_head))) next
    if (!all(grepl(shape, non_empty))) next
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
  override <- (config[["column_types"]] %||% list())[[col]]
  if (!is.null(override)) return(override)
  infer_col_type(x, config[["rules"]][["type_inference_threshold"]] %||% 0.90)
}

#' Canonical report filename for a run
#'
#' Single source of truth for the report filename slug, used by both the
#' snapshot writer (stored in the \code{report_file} column) and the report
#' renderer, so the two can never disagree.
#'
#' @param dataset_name Character. Dataset name.
#' @param run_time POSIXct. The run's single timestamp.
#' @param snapshot_id Integer or \code{NULL}. When supplied, appended to the
#'   slug so two runs of one dataset that start in the same wall-clock second
#'   cannot collide on one filename (the snapshot id is the unique run key).
#' @return Character filename, e.g. \code{"mydata_20260704_101112_47.html"}
#'   (or without the trailing id when \code{snapshot_id} is \code{NULL}).
#' @keywords internal
#' @noRd
report_filename <- function(dataset_name, run_time, snapshot_id = NULL) {
  slug <- format(run_time, "%Y%m%d_%H%M%S", tz = "UTC")
  if (!is.null(snapshot_id)) slug <- paste0(slug, "_", snapshot_id)
  sprintf("%s_%s.html", dataset_name, slug)
}

#' Convert a stored UTC-ISO snapshot timestamp to a local-time display string
#'
#' Single source of truth for turning the \code{run_timestamp} stored in the
#' snapshot DB (UTC ISO, e.g. \code{"2026-07-17T10:11:12Z"}) into the local-time
#' string users see. The QC report renders local time from the live run_time
#' (\code{report.R}, same \code{"\%Y-\%m-\%d \%H:\%M:\%S"} / \code{tz = ""}
#' format) and the GUI history converts too; the drift report goes through here
#' so all three surfaces agree for one instant (B-43). A value that does not
#' parse is returned unchanged rather than shown as \code{NA}.
#' @keywords internal
#' @noRd
utc_to_local_display <- function(ts) {
  parsed <- as.POSIXct(ts, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ifelse(is.na(parsed), ts, format(parsed, "%Y-%m-%d %H:%M:%S", tz = ""))
}

#' Move a file, falling back to copy+delete across filesystems
#'
#' \code{file.rename()} fails (returning FALSE, no error) when source and
#' target are on different filesystems -- e.g. a tempdir render moved to a
#' network-share report directory. Without the fallback the rendered report
#' would silently never arrive while the caller still returns its path.
#'
#' @keywords internal
#' @noRd
.move_file <- function(from, to) {
  if (suppressWarnings(file.rename(from, to))) return(invisible(TRUE))
  if (!file.copy(from, to, overwrite = TRUE))
    rlang::abort(paste0("Failed to move rendered report to: ", to),
                 class = c("dqcheckr_write_error", "dqcheckr_error"))
  unlink(from)
  invisible(TRUE)
}

#' Resolve types for every column of a data frame in one pass
#'
#' Named character vector of \code{resolve_col_type()} results, computed once
#' so the check suite doesn't re-run full-column type inference (five date
#' parses plus a numeric parse per call) for every check that needs a type.
#'
#' @param df A data frame with all columns as character vectors.
#' @param config Named list. Merged configuration.
#' @return Named character vector, one element per column of \code{df}.
#' @keywords internal
#' @noRd
resolve_col_types <- function(df, config) {
  vapply(names(df), function(col) resolve_col_type(col, df[[col]], config),
         character(1))
}

#' Look up the effective threshold for a column, with per-column fallback
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
#' @noRd
col_threshold <- function(config, col, key, default = NULL) {
  col_val <- (config[["column_rules"]] %||% list())[[col]][[key]]
  if (!is.null(col_val)) return(col_val)
  rule_val <- config[["rules"]][[key]]
  if (!is.null(rule_val)) return(rule_val)
  default
}

#' Look up a table-level threshold from config
#'
#' @param config Named list. Merged configuration.
#' @param key Character. Threshold key (e.g. \code{"min_row_count"}).
#' @param default Default value if not found.
#'
#' @return The resolved threshold value.
#' @keywords internal
#' @noRd
table_threshold <- function(config, key, default = NULL) {
  val <- config[["rules"]][[key]]
  if (!is.null(val)) return(val)
  default
}

#' Cap a value vector to at most n entries for display
#'
#' @param vals Character vector of values to display.
#' @param n Maximum number of values to show before truncating.
#' @return A single character string.
#' @keywords internal
#' @noRd
.cap_values <- function(vals, n = 20L) {
  if (length(vals) <= n) return(paste(vals, collapse = ", "))
  paste0(paste(vals[seq_len(n)], collapse = ", "),
         " ... and ", length(vals) - n, " more")
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
