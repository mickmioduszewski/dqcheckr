#' Test for missing or empty values
#' @keywords internal
#' @noRd
.missing_vals <- function(x) is.na(x) | x == ""

# QC functions -----------------------------------------------------------------

#' QC-01: Check missing rate per column
#'
#' Returns a \code{\link{dq_result}} per column flagging columns whose
#' proportion of missing or empty values exceeds \code{max_missing_rate}.
#'
#' @param df A data frame with all columns as character vectors.
#' @param config Named list as returned by \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects, one per column.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_missing_rate(df, cfg)
#'
#' @export
check_missing_rate <- function(df, config) {
  lapply(names(df), function(col) {
    threshold     <- col_threshold(config, col, "max_missing_rate", 0.05)
    missing_count <- sum(.missing_vals(df[[col]]))
    missing_rate  <- missing_count / nrow(df)
    status <- if (missing_rate > threshold) "FAIL" else "PASS"
    dq_result(
      check_id   = "QC-01",
      check_name = "Missing rate",
      column     = col,
      status     = status,
      observed   = sprintf("%.1f%% missing (%d of %d)",
                           missing_rate * 100, missing_count, nrow(df)),
      threshold  = sprintf("%.1f%%", threshold * 100),
      message    = if (status == "FAIL")
        sprintf("Column '%s' missing rate %.1f%% exceeds threshold %.1f%%.",
                col, missing_rate * 100, threshold * 100)
      else
        sprintf("Column '%s' missing rate is within threshold.", col)
    )
  })
}

#' QC-02: Check for entirely empty columns
#'
#' Returns a \code{\link{dq_result}} per column. A column is considered empty
#' when every value is \code{NA} or the empty string \code{""}.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects, one per column.
#'   Status is \code{"FAIL"} for entirely empty columns; \code{"PASS"}
#'   otherwise.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_empty_column(df, cfg)
#'
#' @export
check_empty_column <- function(df, config) {
  lapply(names(df), function(col) {
    is_empty <- all(.missing_vals(df[[col]]))
    dq_result(
      check_id   = "QC-02",
      check_name = "Empty column",
      column     = col,
      status     = if (is_empty) "FAIL" else "PASS",
      observed   = if (is_empty) "100% empty" else "Not empty",
      message    = if (is_empty)
        sprintf("Column '%s' is entirely empty.", col)
      else
        sprintf("Column '%s' has at least one non-empty value.", col)
    )
  })
}

#' QC-03: Check for fully-duplicate rows
#'
#' Returns a single \code{\link{dq_result}} for the whole table. A row is
#' considered a duplicate when every column value is identical to another row.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}. Currently unused; present for API consistency.
#'
#' @return A list containing one \code{\link{dq_result}}.
#'   Status is \code{"WARN"} if any duplicate rows exist; \code{"PASS"}
#'   otherwise.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_duplicate_rows(df, cfg)
#'
#' @export
check_duplicate_rows <- function(df, config) {
  n_dups <- sum(duplicated(df))
  status <- if (n_dups > 0) "WARN" else "PASS"
  list(dq_result(
    check_id   = "QC-03",
    check_name = "Duplicate rows",
    status     = status,
    observed   = sprintf("%d fully-duplicate row(s)", n_dups),
    message    = if (n_dups > 0)
      sprintf("%d row(s) are exact duplicates of another row.", n_dups)
    else
      "No fully-duplicate rows found."
  ))
}

#' QC-04: Report row count
#'
#' Returns a single \code{"INFO"} \code{\link{dq_result}} recording the number
#' of rows in the data frame. Never fails or warns; use
#' \code{\link{check_min_row_count}} for threshold-based row count checks.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}. Currently unused; present for API consistency.
#'
#' @return A list containing one \code{\link{dq_result}} with status
#'   \code{"INFO"}.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_row_count(df, cfg)
#'
#' @export
check_row_count <- function(df, config) {
  list(dq_result(
    check_id   = "QC-04",
    check_name = "Row count",
    status     = "INFO",
    observed   = as.character(nrow(df)),
    message    = sprintf("File contains %d rows.", nrow(df))
  ))
}

#' QC-05: Report column count
#'
#' Returns a single \code{"INFO"} \code{\link{dq_result}} recording the number
#' of columns in the data frame. Never fails or warns.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}. Currently unused; present for API consistency.
#'
#' @return A list containing one \code{\link{dq_result}} with status
#'   \code{"INFO"}.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_col_count(df, cfg)
#'
#' @export
check_col_count <- function(df, config) {
  list(dq_result(
    check_id   = "QC-05",
    check_name = "Column count",
    status     = "INFO",
    observed   = as.character(ncol(df)),
    message    = sprintf("File contains %d columns.", ncol(df))
  ))
}

#' QC-06: Report inferred column types
#'
#' Returns one \code{"INFO"} \code{\link{dq_result}} per column recording the
#' type resolved by \code{\link{resolve_col_type}} (\code{"date"},
#' \code{"numeric"}, \code{"character"}, or \code{"unknown"}).
#' Per-column overrides from \code{config$column_types} are respected.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects, one per column, all with
#'   status \code{"INFO"}.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_inferred_types(df, cfg)
#'
#' @export
check_inferred_types <- function(df, config) {
  lapply(names(df), function(col) {
    typ <- resolve_col_type(col, df[[col]], config)
    dq_result(
      check_id   = "QC-06",
      check_name = "Inferred type",
      column     = col,
      status     = "INFO",
      observed   = typ,
      message    = sprintf("Column '%s' inferred as %s.", col, typ)
    )
  })
}

#' QC-07: Report numeric summary statistics
#'
#' For each column whose resolved type is \code{"numeric"}, returns one
#' \code{"INFO"} \code{\link{dq_result}} containing min, max, mean, and
#' standard deviation of the parseable values. Columns inferred as non-numeric
#' are silently skipped.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects (one per numeric column),
#'   all with status \code{"INFO"}. Returns an empty list if no numeric columns
#'   are found.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_numeric_stats(df, cfg)
#'
#' @importFrom stats sd
#' @export
check_numeric_stats <- function(df, config) {
  results <- list()
  for (col in names(df)) {
    if (resolve_col_type(col, df[[col]], config) != "numeric") next
    vals <- suppressWarnings(as.numeric(df[[col]]))
    vals <- vals[!is.na(vals)]
    if (length(vals) == 0) next
    results <- c(results, list(dq_result(
      check_id   = "QC-07",
      check_name = "Numeric stats",
      column     = col,
      status     = "INFO",
      observed   = sprintf("min=%.4g, max=%.4g, mean=%.4g, sd=%.4g",
                           min(vals), max(vals), mean(vals),
                           if (length(vals) > 1) sd(vals) else NA_real_),
      message    = sprintf("Summary statistics for numeric column '%s'.", col)
    )))
  }
  results
}

#' QC-08: Report distinct value counts for character columns
#'
#' For each column whose resolved type is \code{"character"}, returns one
#' \code{"INFO"} \code{\link{dq_result}} with the count of distinct non-empty
#' values. Columns inferred as numeric or date are silently skipped.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects (one per character column),
#'   all with status \code{"INFO"}. Returns an empty list if no character
#'   columns are found.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_distinct_counts(df, cfg)
#'
#' @export
check_distinct_counts <- function(df, config) {
  results <- list()
  for (col in names(df)) {
    if (resolve_col_type(col, df[[col]], config) != "character") next
    n_distinct <- length(unique(df[[col]][!.missing_vals(df[[col]])]))
    results <- c(results, list(dq_result(
      check_id   = "QC-08",
      check_name = "Distinct value count",
      column     = col,
      status     = "INFO",
      observed   = as.character(n_distinct),
      message    = sprintf("Column '%s' has %d distinct non-empty value(s).",
                           col, n_distinct)
    )))
  }
  results
}

#' QC-09: Check for values outside the allowed set
#'
#' For each column that has \code{allowed_values} configured in
#' \code{config$column_rules}, returns a \code{\link{dq_result}} flagging any
#' non-empty values not in the allowed list. Returns an empty list when no
#' \code{allowed_values} rules are configured.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects, one per configured column.
#'   Status is \code{"FAIL"} when unexpected values are found; \code{"PASS"}
#'   otherwise. Returns an empty list if no \code{allowed_values} rules are
#'   configured.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_allowed_values(df, cfg)
#'
#' @export
check_allowed_values <- function(df, config) {
  results   <- list()
  col_rules <- config$column_rules %||% list()
  for (col in names(col_rules)) {
    allowed <- col_rules[[col]]$allowed_values
    if (is.null(allowed) || !col %in% names(df)) next
    vals <- df[[col]][!.missing_vals(df[[col]])]
    bad  <- setdiff(unique(vals), allowed)
    status <- if (length(bad) > 0) "FAIL" else "PASS"
    results <- c(results, list(dq_result(
      check_id   = "QC-09",
      check_name = "Allowed values",
      column     = col,
      status     = status,
      observed   = if (length(bad) > 0)
        paste("Unexpected values:", .cap_values(bad))
      else
        "All values are in the allowed list.",
      threshold  = paste("Allowed:", paste(allowed, collapse = ", ")),
      message    = if (length(bad) > 0)
        sprintf("Column '%s' contains %d unexpected value(s): %s.",
                col, length(bad), .cap_values(bad))
      else
        sprintf("Column '%s' contains only allowed values.", col)
    )))
  }
  results
}

#' QC-10: Check for out-of-range numeric values
#'
#' For each column that has \code{min_value} or \code{max_value} configured in
#' \code{config$column_rules}, returns a \code{\link{dq_result}} flagging any
#' values that fall outside the specified range. Returns an empty list when no
#' bound rules are configured.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects, one per configured column.
#'   Status is \code{"FAIL"} when out-of-range values are found; \code{"PASS"}
#'   otherwise. Returns an empty list if no bound rules are configured.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_numeric_bounds(df, cfg)
#'
#' @importFrom utils head
#' @export
check_numeric_bounds <- function(df, config) {
  results   <- list()
  col_rules <- config$column_rules %||% list()
  for (col in names(col_rules)) {
    min_val <- col_rules[[col]]$min_value
    max_val <- col_rules[[col]]$max_value
    if (is.null(min_val) && is.null(max_val)) next
    if (!col %in% names(df)) next
    vals    <- suppressWarnings(as.numeric(df[[col]]))
    violate <- character(0)
    if (!is.null(min_val)) {
      below   <- df[[col]][!is.na(vals) & vals < min_val]
      violate <- c(violate, unique(below))
    }
    if (!is.null(max_val)) {
      above   <- df[[col]][!is.na(vals) & vals > max_val]
      violate <- c(violate, unique(above))
    }
    violate <- unique(violate)
    status  <- if (length(violate) > 0) "FAIL" else "PASS"
    thr_parts <- c(
      if (!is.null(min_val)) paste("min:", min_val),
      if (!is.null(max_val)) paste("max:", max_val)
    )
    results <- c(results, list(dq_result(
      check_id   = "QC-10",
      check_name = "Numeric bounds",
      column     = col,
      status     = status,
      observed   = if (length(violate) > 0)
        paste("Out-of-range values:", paste(head(violate, 5), collapse = ", "))
      else
        "All values are within bounds.",
      threshold  = paste(thr_parts, collapse = "; "),
      message    = if (length(violate) > 0)
        sprintf("Column '%s' has %d out-of-range value(s).", col, length(violate))
      else
        sprintf("Column '%s' values are all within bounds.", col)
    )))
  }
  results
}

#' QC-11: Check non-numeric rate in numeric columns
#'
#' For each column whose resolved type is \code{"numeric"}, computes the
#' proportion of non-empty values that cannot be coerced to numeric. Returns
#' \code{"FAIL"} when the rate exceeds \code{max_non_numeric_rate} (default
#' 0.01), \code{"WARN"} when it exceeds \code{warn_non_numeric_rate} (default
#' 0), and \code{"PASS"} otherwise. Both thresholds support per-column
#' overrides via \code{config$column_rules}.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects, one per numeric column.
#'   Returns an empty list if no numeric columns are found.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_non_numeric(df, cfg)
#'
#' @export
check_non_numeric <- function(df, config) {
  results <- list()
  for (col in names(df)) {
    if (resolve_col_type(col, df[[col]], config) != "numeric") next
    non_empty <- df[[col]][!.missing_vals(df[[col]])]
    if (length(non_empty) == 0) next
    bad  <- non_empty[is.na(suppressWarnings(as.numeric(non_empty)))]
    rate <- length(bad) / length(non_empty)

    fail_threshold <- col_threshold(config, col, "max_non_numeric_rate", 0.01)
    warn_threshold <- col_threshold(config, col, "warn_non_numeric_rate", 0.0)

    status <- if (rate > fail_threshold) "FAIL" else if (rate > warn_threshold) "WARN" else "PASS"

    results <- c(results, list(dq_result(
      check_id   = "QC-11",
      check_name = "Non-numeric values",
      column     = col,
      status     = status,
      observed   = sprintf("%d non-numeric value(s) (%.2f%%)",
                           length(bad), rate * 100),
      threshold  = sprintf("WARN >%.2f%%, FAIL >%.2f%%",
                           warn_threshold * 100, fail_threshold * 100),
      message    = switch(status,
        FAIL = sprintf("Column '%s' non-numeric rate %.2f%% exceeds threshold %.2f%%.",
                       col, rate * 100, fail_threshold * 100),
        WARN = sprintf("Column '%s' has %d non-numeric value(s) below FAIL threshold.",
                       col, length(bad)),
        PASS = sprintf("Column '%s' has no non-numeric values.", col)
      )
    )))
  }
  results
}

#' QC-12: Check uniqueness of key column(s)
#'
#' Checks that the column(s) listed in \code{config$key_columns} have no
#' duplicate values. When \code{key_columns} is a single string, one result is
#' returned for that column. When it is a character vector of length > 1, a
#' single result covering the composite key is returned. Returns an empty list
#' if \code{key_columns} is not configured.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects. Status is \code{"FAIL"}
#'   when duplicates or missing key columns are detected; \code{"PASS"}
#'   otherwise. Returns an empty list if \code{key_columns} is not configured.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_key_uniqueness(df, cfg)
#'
#' @export
check_key_uniqueness <- function(df, config) {
  keys <- config$key_columns
  if (is.null(keys) || length(keys) == 0) return(list())

  if (length(keys) == 1) {
    # Single-column path (original behaviour)
    col <- keys
    if (!col %in% names(df)) {
      return(list(dq_result(
        check_id   = "QC-12",
        check_name = "Key uniqueness",
        column     = col,
        status     = "FAIL",
        observed   = "Column not found in file",
        message    = sprintf("Key column '%s' is not present in the file.", col)
      )))
    }
    n_dups <- sum(duplicated(df[[col]]))
    status <- if (n_dups > 0) "FAIL" else "PASS"
    return(list(dq_result(
      check_id   = "QC-12",
      check_name = "Key uniqueness",
      column     = col,
      status     = status,
      observed   = sprintf("%d duplicate value(s) found", n_dups),
      message    = if (n_dups > 0)
        sprintf("Key column '%s' has %d duplicate value(s).", col, n_dups)
      else
        sprintf("Key column '%s' has all unique values.", col)
    )))
  }

  # Composite key path
  missing_keys <- setdiff(keys, names(df))
  if (length(missing_keys) > 0) {
    return(list(dq_result(
      check_id   = "QC-12",
      check_name = "Composite key uniqueness",
      status     = "FAIL",
      observed   = paste("Missing columns:", paste(missing_keys, collapse = ", ")),
      message    = sprintf("Composite key column(s) missing from file: %s.",
                           paste(missing_keys, collapse = ", "))
    )))
  }
  key_df <- df[, keys, drop = FALSE]
  n_dups <- sum(duplicated(key_df))
  status <- if (n_dups > 0) "FAIL" else "PASS"
  list(dq_result(
    check_id   = "QC-12",
    check_name = "Composite key uniqueness",
    status     = status,
    observed   = sprintf("%d duplicate composite key row(s) found", n_dups),
    threshold  = paste("Key columns:", paste(keys, collapse = ", ")),
    message    = if (n_dups > 0)
      sprintf("Composite key (%s) has %d duplicate row(s).",
              paste(keys, collapse = ", "), n_dups)
    else
      sprintf("Composite key (%s) has all unique values.",
              paste(keys, collapse = ", "))
  ))
}

#' QC-13: Check values against a regex pattern
#'
#' For each column that has a \code{pattern} configured in
#' \code{config$column_rules}, returns a \code{\link{dq_result}} reporting how
#' many non-empty values do not match the Perl-compatible regular expression.
#' Returns an empty list when no pattern rules are configured.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects, one per configured column.
#'   Status is \code{"FAIL"} when any values violate the pattern; \code{"PASS"}
#'   otherwise. Returns an empty list if no pattern rules are configured.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_pattern(df, cfg)
#'
#' @export
check_pattern <- function(df, config) {
  results   <- list()
  col_rules <- config$column_rules %||% list()
  for (col in names(col_rules)) {
    pattern <- col_rules[[col]]$pattern
    if (is.null(pattern) || !col %in% names(df)) next
    non_empty  <- df[[col]][!.missing_vals(df[[col]])]
    bad_count  <- sum(!grepl(pattern, non_empty, perl = TRUE))
    status     <- if (bad_count > 0) "FAIL" else "PASS"
    results <- c(results, list(dq_result(
      check_id   = "QC-13",
      check_name = "Pattern / regex",
      column     = col,
      status     = status,
      observed   = sprintf("%d value(s) do not match pattern", bad_count),
      threshold  = pattern,
      message    = if (bad_count > 0)
        sprintf("Column '%s': %d value(s) violate pattern '%s'.",
                col, bad_count, pattern)
      else
        sprintf("Column '%s': all values match pattern '%s'.", col, pattern)
    )))
  }
  results
}

#' QC-14: Check row count bounds and optional file size
#'
#' Runs up to three sub-checks, each returning a separate
#' \code{\link{dq_result}}:
#' \enumerate{
#'   \item \strong{File size} — only when \code{file_path} is supplied and
#'     \code{max_file_size_mb} is configured in \code{rules}: FAIL if the file
#'     exceeds the size limit.
#'   \item \strong{Minimum row count} — FAIL if \code{row_count <
#'     min_row_count}. Skipped (PASS with a note) when \code{min_row_count}
#'     is \code{0}.
#'   \item \strong{Maximum row count} — only when \code{max_row_count} is
#'     configured in \code{rules}: FAIL if \code{row_count > max_row_count}.
#' }
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#' @param file_path Character or \code{NULL}. Absolute path to the file on
#'   disk, required for the optional file-size sub-check.
#'
#' @return A list of \code{\link{dq_result}} objects (one to three entries
#'   depending on which sub-checks are active).
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_min_row_count(df, cfg, file_path = path)
#'
#' @export
check_min_row_count <- function(df, config, file_path = NULL) {
  results <- list()

  # File size check (runs before row count; requires file_path)
  if (!is.null(file_path) && file.exists(file_path)) {
    max_mb <- table_threshold(config, "max_file_size_mb")
    if (!is.null(max_mb)) {
      fsize_mb <- file.info(file_path)$size / 1024 / 1024
      status   <- if (fsize_mb > max_mb) "FAIL" else "PASS"
      results <- c(results, list(dq_result(
        check_id   = "QC-14",
        check_name = "File size",
        status     = status,
        observed   = sprintf("%.2f MB", fsize_mb),
        threshold  = sprintf("%.2f MB maximum", max_mb),
        message    = if (status == "FAIL")
          sprintf("File size %.2f MB exceeds maximum of %.2f MB.", fsize_mb, max_mb)
        else
          sprintf("File size %.2f MB is within the limit.", fsize_mb)
      )))
    }
  }

  min_rc <- table_threshold(config, "min_row_count", 0)
  if (min_rc > 0) {
    status <- if (nrow(df) < min_rc) "FAIL" else "PASS"
    results <- c(results, list(dq_result(
      check_id   = "QC-14",
      check_name = "Minimum row count",
      status     = status,
      observed   = sprintf("%d rows", nrow(df)),
      threshold  = sprintf("%d rows minimum", min_rc),
      message    = if (status == "FAIL")
        sprintf("File has %d rows, below the minimum of %d.", nrow(df), min_rc)
      else
        sprintf("File has %d rows, meeting the minimum of %d.", nrow(df), min_rc)
    )))
  } else {
    results <- c(results, list(dq_result(
      check_id   = "QC-14",
      check_name = "Minimum row count",
      status     = "PASS",
      observed   = as.character(nrow(df)),
      message    = "Minimum row count check is disabled (min_row_count = 0)."
    )))
  }

  max_rc <- table_threshold(config, "max_row_count")
  if (!is.null(max_rc)) {
    status <- if (nrow(df) > max_rc) "FAIL" else "PASS"
    results <- c(results, list(dq_result(
      check_id   = "QC-14",
      check_name = "Maximum row count",
      status     = status,
      observed   = sprintf("%d rows", nrow(df)),
      threshold  = sprintf("%d rows maximum", max_rc),
      message    = if (status == "FAIL")
        sprintf("File has %d rows, exceeding the maximum of %d.", nrow(df), max_rc)
      else
        sprintf("File has %d rows, within the maximum of %d.", nrow(df), max_rc)
    )))
  }

  results
}

#' QC-15: Detect statistical outliers in numeric columns
#'
#' For each column whose resolved type is \code{"numeric"}, applies up to two
#' outlier detection methods (combined with logical OR):
#' \enumerate{
#'   \item \strong{Z-score}: values whose absolute Z-score exceeds
#'     \code{max_z_score} are flagged.
#'   \item \strong{IQR fence}: values below \code{Q1 - k * IQR} or above
#'     \code{Q3 + k * IQR} (where \code{k = iqr_fence_multiplier}) are
#'     flagged.
#' }
#' Both thresholds support per-column overrides via \code{config$column_rules}.
#' A column is skipped (PASS with a note) when neither threshold is configured
#' or when it has fewer than four parseable values.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects, one per numeric column.
#'   Status is \code{"FAIL"} when outliers are detected; \code{"PASS"}
#'   otherwise. Returns an empty list if no numeric columns are found.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_outliers(df, cfg)
#'
#' @importFrom stats median IQR quantile
#' @export
check_outliers <- function(df, config) {
  results <- list()
  for (col in names(df)) {
    if (resolve_col_type(col, df[[col]], config) != "numeric") next

    max_z  <- col_threshold(config, col, "max_z_score")
    iqr_k  <- col_threshold(config, col, "iqr_fence_multiplier")

    if (is.null(max_z) && is.null(iqr_k)) {
      results <- c(results, list(dq_result(
        check_id   = "QC-15",
        check_name = "Outlier detection",
        column     = col,
        status     = "PASS",
        observed   = "No outlier threshold configured.",
        message    = sprintf("Column '%s': outlier check skipped (no threshold).", col)
      )))
      next
    }

    vals <- suppressWarnings(as.numeric(df[[col]]))
    nn   <- vals[!is.na(vals)]
    if (length(nn) < 4) {
      results <- c(results, list(dq_result(
        check_id   = "QC-15",
        check_name = "Outlier detection",
        column     = col,
        status     = "PASS",
        observed   = sprintf("%d parseable values -- too few to test.", length(nn)),
        message    = sprintf("Column '%s': outlier check skipped (fewer than 4 values).", col)
      )))
      next
    }

    outlier_idx <- logical(length(nn))

    if (!is.null(max_z)) {
      mn  <- mean(nn)
      sdev <- sd(nn)
      if (sdev > 0)
        outlier_idx <- outlier_idx | (abs((nn - mn) / sdev) > max_z)
    }

    if (!is.null(iqr_k)) {
      q1  <- quantile(nn, 0.25)
      q3  <- quantile(nn, 0.75)
      iqr <- IQR(nn)
      outlier_idx <- outlier_idx | (nn < q1 - iqr_k * iqr) | (nn > q3 + iqr_k * iqr)
    }

    n_out  <- sum(outlier_idx)
    status <- if (n_out > 0) "FAIL" else "PASS"
    thr_parts <- c(
      if (!is.null(max_z))  sprintf("max z-score: %.1f", max_z),
      if (!is.null(iqr_k)) sprintf("IQR multiplier: %.1f", iqr_k)
    )
    results <- c(results, list(dq_result(
      check_id   = "QC-15",
      check_name = "Outlier detection",
      column     = col,
      status     = status,
      observed   = if (n_out > 0)
        sprintf("%d outlier(s) (%.1f%%): %s",
                n_out, n_out / length(nn) * 100,
                .cap_values(as.character(nn[outlier_idx]), 10L))
      else
        "No outliers detected.",
      threshold  = paste(thr_parts, collapse = "; "),
      message    = if (n_out > 0)
        sprintf("Column '%s' has %d outlier(s) (%.1f%%).", col, n_out,
                n_out / length(nn) * 100)
      else
        sprintf("Column '%s': no outliers detected.", col)
    )))
  }
  results
}

#' SC-01 / SC-02: Check columns against the expected schema contract
#'
#' Compares the columns present in \code{df} against
#' \code{config$expected_columns}:
#' \itemize{
#'   \item \strong{SC-01}: one \code{"FAIL"} result per column present in the
#'     file but not listed in \code{expected_columns}.
#'   \item \strong{SC-02}: one \code{"FAIL"} result per column listed in
#'     \code{expected_columns} but absent from the file.
#' }
#' Returns an empty list if \code{expected_columns} is not configured.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects. Each schema violation
#'   produces one \code{"FAIL"} result; a \code{"PASS"} result is emitted for
#'   each sub-check when no violations are found. Returns an empty list if
#'   \code{expected_columns} is not configured.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_schema_contract(df, cfg)
#'
#' @export
check_schema_contract <- function(df, config) {
  expected <- config$expected_columns
  if (is.null(expected)) return(list())

  results <- list()

  extra <- setdiff(names(df), expected)
  if (length(extra) > 0) {
    for (col in extra)
      results <- c(results, list(dq_result(
        check_id   = "SC-01",
        check_name = "Unexpected column",
        column     = col,
        status     = "FAIL",
        observed   = sprintf("Column '%s' is not in the expected schema.", col),
        message    = sprintf("Column '%s' is present in the file but not in expected_columns.", col)
      )))
  } else {
    results <- c(results, list(dq_result(
      check_id   = "SC-01",
      check_name = "Unexpected column",
      status     = "PASS",
      observed   = "No unexpected columns.",
      message    = "All file columns are in the expected schema."
    )))
  }

  missing_cols <- setdiff(expected, names(df))
  if (length(missing_cols) > 0) {
    for (col in missing_cols)
      results <- c(results, list(dq_result(
        check_id   = "SC-02",
        check_name = "Missing expected column",
        column     = col,
        status     = "FAIL",
        observed   = sprintf("Expected column '%s' is absent.", col),
        message    = sprintf("Column '%s' is in expected_columns but absent from the file.", col)
      )))
  } else {
    results <- c(results, list(dq_result(
      check_id   = "SC-02",
      check_name = "Missing expected column",
      status     = "PASS",
      observed   = "All expected columns are present.",
      message    = "No expected columns are missing from the file."
    )))
  }

  results
}

#' Run all generic quality checks on a dataset
#'
#' Runs the full QC check suite (QC-01 to QC-15, SC-01, SC-02) against a
#' single data frame snapshot.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#' @param file_path Character or \code{NULL}. Absolute path to the file, used
#'   for the optional \code{max_file_size_mb} check in QC-14.
#'
#' @return A list of \code{\link{dq_result}} objects.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg     <- load_config("starwars_csv", config_dir = cfg_dir)
#' path    <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df      <- read_dataset(path, cfg)
#' results <- run_qc_checks(df, cfg)
#'
#' @export
run_qc_checks <- function(df, config, file_path = NULL) {
  c(
    check_missing_rate(df, config),
    check_empty_column(df, config),
    check_duplicate_rows(df, config),
    check_row_count(df, config),
    check_col_count(df, config),
    check_inferred_types(df, config),
    check_numeric_stats(df, config),
    check_distinct_counts(df, config),
    check_allowed_values(df, config),
    check_numeric_bounds(df, config),
    check_non_numeric(df, config),
    check_key_uniqueness(df, config),
    check_pattern(df, config),
    check_min_row_count(df, config, file_path = file_path),
    check_outliers(df, config),
    check_schema_contract(df, config)
  )
}
