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
    # 0/0 would be NaN and poison the threshold comparison; an empty file is
    # reported as a FAIL by QC-14 ("Empty file"), so rates are defined as 0.
    missing_rate  <- if (nrow(df) > 0) missing_count / nrow(df) else 0
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
#' @param types Optional named character vector of pre-resolved column types
#'   (one element per column, as produced by \code{\link{resolve_col_type}}).
#'   When \code{NULL} (the default), types are resolved internally. Supplying
#'   this avoids re-running type inference when several checks share one data
#'   frame.
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
check_inferred_types <- function(df, config, types = NULL) {
  types <- types %||% resolve_col_types(df, config)
  lapply(names(df), function(col) {
    typ <- types[[col]]
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
#' @param types Optional named character vector of pre-resolved column types;
#'   see \code{\link{check_inferred_types}}.
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
check_numeric_stats <- function(df, config, types = NULL) {
  types <- types %||% resolve_col_types(df, config)
  results <- list()
  for (col in names(df)) {
    if (types[[col]] != "numeric") next
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
#' @param types Optional named character vector of pre-resolved column types;
#'   see \code{\link{check_inferred_types}}.
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
check_distinct_counts <- function(df, config, types = NULL) {
  types <- types %||% resolve_col_types(df, config)
  results <- list()
  for (col in names(df)) {
    if (types[[col]] != "character") next
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
  col_rules <- config[["column_rules"]] %||% list()
  for (col in names(col_rules)) {
    allowed <- col_rules[[col]]$allowed_values
    if (is.null(allowed) || !col %in% names(df)) next
    allowed_vec <- unlist(allowed, use.names = FALSE)
    # The numerically-typed subset of the allowed list, kept separate from the
    # character form. A mixed YAML list like [2.1, 3.5, "N/A"] unlists to an
    # all-character vector, so gating on is.numeric(allowed_vec) would skip the
    # numeric comparison entirely and FAIL a file value of "2.10" (B-22). Only
    # genuinely-numeric entries are compared numerically, so a *string* "007"
    # still does not accept a file value of "7".
    num_allowed <- unlist(allowed[vapply(allowed, is.numeric, logical(1))],
                          use.names = FALSE)
    vals <- df[[col]][!.missing_vals(df[[col]])]
    bad  <- setdiff(unique(vals), as.character(allowed_vec))
    if (length(bad) > 0 && length(num_allowed) > 0) {
      bad_num <- suppressWarnings(as.numeric(bad))
      bad <- bad[is.na(bad_num) | !bad_num %in% num_allowed]
    }
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
      threshold  = paste("Allowed:", paste(allowed_vec, collapse = ", ")),
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
  col_rules <- config[["column_rules"]] %||% list()
  for (col in names(col_rules)) {
    min_val <- col_rules[[col]]$min_value
    max_val <- col_rules[[col]]$max_value
    if (is.null(min_val) && is.null(max_val)) next
    if (!col %in% names(df)) next
    vals <- suppressWarnings(as.numeric(df[[col]]))
    # Count violating ROWS; a million rows of the same bad value must not
    # read as "1 out-of-range value". Unique values are kept for display.
    viol <- rep(FALSE, length(vals))
    if (!is.null(min_val)) viol <- viol | (!is.na(vals) & vals < min_val)
    if (!is.null(max_val)) viol <- viol | (!is.na(vals) & vals > max_val)
    n_rows   <- sum(viol)
    examples <- unique(df[[col]][viol])
    status   <- if (n_rows > 0) "FAIL" else "PASS"
    thr_parts <- c(
      if (!is.null(min_val)) paste("min:", min_val),
      if (!is.null(max_val)) paste("max:", max_val)
    )
    results <- c(results, list(dq_result(
      check_id   = "QC-10",
      check_name = "Numeric bounds",
      column     = col,
      status     = status,
      observed   = if (n_rows > 0)
        paste("Out-of-range values:", paste(head(examples, 5), collapse = ", "))
      else
        "All values are within bounds.",
      threshold  = paste(thr_parts, collapse = "; "),
      message    = if (n_rows > 0)
        sprintf("Column '%s' has %d out-of-range row(s) (%d distinct value(s)).",
                col, n_rows, length(examples))
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
#' @param types Optional named character vector of pre-resolved column types;
#'   see \code{\link{check_inferred_types}}.
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
check_non_numeric <- function(df, config, types = NULL) {
  types <- types %||% resolve_col_types(df, config)
  results <- list()
  for (col in names(df)) {
    if (types[[col]] != "numeric") next
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
  keys <- config[["key_columns"]]
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
  col_rules <- config[["column_rules"]] %||% list()
  for (col in names(col_rules)) {
    pattern <- col_rules[[col]]$pattern
    if (is.null(pattern) || !col %in% names(df)) next
    non_empty  <- df[[col]][!.missing_vals(df[[col]])]
    # An invalid regex in hand-edited YAML must fail this check, not abort
    # the whole run with a raw grepl() error (PCRE also emits a compilation
    # warning before the error — suppress it; the FAIL result carries the
    # message).
    bad_count  <- tryCatch(
      suppressWarnings(sum(!grepl(pattern, non_empty, perl = TRUE))),
      error = function(e) e)
    if (inherits(bad_count, "error")) {
      results <- c(results, list(dq_result(
        check_id   = "QC-13",
        check_name = "Pattern / regex",
        column     = col,
        status     = "FAIL",
        observed   = "Pattern could not be evaluated",
        threshold  = pattern,
        message    = sprintf("Column '%s': invalid regex pattern '%s' (%s).",
                             col, pattern, conditionMessage(bad_count))
      )))
      next
    }
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
#' Runs up to four sub-checks, each returning a separate
#' \code{\link{dq_result}}:
#' \enumerate{
#'   \item \strong{Empty file} -- FAIL when the file contains no data rows at
#'     all. Emitted unconditionally (independent of \code{min_row_count}) so
#'     that an empty delivery always fails the run.
#'   \item \strong{File size} -- only when \code{file_path} is supplied and
#'     \code{max_file_size_mb} is configured in \code{rules}: FAIL if the file
#'     exceeds the size limit.
#'   \item \strong{Minimum row count} -- FAIL if \code{row_count <
#'     min_row_count}. Skipped (PASS with a note) when \code{min_row_count}
#'     is \code{0}.
#'   \item \strong{Maximum row count} -- only when \code{max_row_count} is
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
#' @return A list of \code{\link{dq_result}} objects (one to four entries
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

  # Empty-file check: a delivery with zero data rows must always FAIL,
  # regardless of whether min_row_count is configured.
  if (nrow(df) == 0) {
    results <- c(results, list(dq_result(
      check_id   = "QC-14",
      check_name = "Empty file",
      status     = "FAIL",
      observed   = "0 rows",
      message    = "File contains no data rows."
    )))
  }

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
#' @param types Optional named character vector of pre-resolved column types;
#'   see \code{\link{check_inferred_types}}.
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
check_outliers <- function(df, config, types = NULL) {
  types <- types %||% resolve_col_types(df, config)
  results <- list()
  for (col in names(df)) {
    if (types[[col]] != "numeric") next

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
    # Drop non-finite parses (Inf/-Inf): they make sd() return NaN, and the
    # downstream `if (sdev > 0)` / comparison then aborts on a missing value.
    nn   <- vals[is.finite(vals)]
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

#' QC-16: File encoding sanity
#'
#' Verifies that the delivered file's bytes matched the encoding declared in
#' the config. \code{\link{read_dataset}} scans the whole file for UTF-8
#' validity before parsing (when the effective encoding is UTF-8) and records
#' the outcome on the returned data frame; this check turns that outcome into
#' a result:
#' \itemize{
#'   \item \strong{PASS} when the file was valid UTF-8 as declared, or when a
#'     declared single-byte encoding (e.g. \code{ISO-8859-1},
#'     \code{Windows-1252}) made a validity scan meaningless -- every byte
#'     sequence is valid in those encodings by construction.
#'   \item \strong{FAIL} when the file was not valid UTF-8 as declared. The
#'     run still completes: the file is read using a single-byte fallback
#'     encoding, and the message reports the detector's best guess at the
#'     actual encoding so the config can be corrected.
#'   \item \strong{WARN} when the declared encoding is multi-byte or unknown
#'     (e.g. \code{UTF-16LE}, \code{Shift-JIS}): dqcheckr scans only UTF-8, so
#'     such a file is read as declared but its validity is not verified -- it is
#'     never reported as "valid by construction".
#'   \item \strong{WARN} when the UTF-8 scan itself could not complete (for
#'     example out of memory on a very large delivery): validity is unknown, so
#'     it is neither a clean PASS nor a definitive FAIL.
#' }
#' A supplier can change their export encoding between deliveries, which is
#' why this runs against every delivery rather than only at configuration
#' time. Returns an empty list when \code{df} did not come from
#' \code{\link{read_dataset}} (no scan outcome to report).
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}. Present for interface consistency; the scan
#'   outcome travels with \code{df}.
#'
#' @return A list with one \code{\link{dq_result}} object, or an empty list
#'   when no scan outcome is attached to \code{df}.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#' check_file_encoding(df, cfg)
#'
#' @export
check_file_encoding <- function(df, config) {
  info <- attr(df, "dq_encoding", exact = TRUE)
  if (is.null(info)) return(list())
  enc_class <- info$enc_class %||% "utf8"

  # Definitive failure first: the file was not valid UTF-8 as declared.
  if (isFALSE(info$valid)) {
    guess_txt <- if (!is.null(info$guess))
      sprintf(" The bytes look like %s.", info$guess)
    else
      " The actual encoding could not be determined."
    return(list(dq_result(
      check_id   = "QC-16",
      check_name = "File encoding",
      status     = "FAIL",
      observed   = sprintf("Not valid %s; read as %s for this run.%s",
                           info$declared, info$used, guess_txt),
      threshold  = sprintf("declared: %s", info$declared),
      message    = sprintf(paste0(
        "File is not valid %s as declared in the config.%s ",
        "It was read as %s so this run could complete; verify the supplier's ",
        "export encoding and update 'encoding' in the dataset config."),
        info$declared, guess_txt, info$used)
    )))
  }

  # A declared multi-byte or unknown encoding (UTF-16/32, Shift-JIS, ...) is not
  # validity-checked -- dqcheckr only scans UTF-8. Do not claim it is "valid by
  # construction"; WARN that it was read as declared without verification.
  if (enc_class == "other") {
    return(list(dq_result(
      check_id   = "QC-16",
      check_name = "File encoding",
      status     = "WARN",
      observed   = sprintf(paste0("'%s' is a multi-byte or unknown encoding that ",
                                  "dqcheckr does not validity-check."), info$used),
      threshold  = sprintf("declared: %s", info$declared),
      message    = paste0("File encoding was not verified: only UTF-8 and ",
                          "single-byte encodings are checked. The file was read ",
                          "as declared. Prefer a UTF-8 export where possible.")
    )))
  }

  if (isTRUE(info$valid)) {
    return(list(dq_result(
      check_id   = "QC-16",
      check_name = "File encoding",
      status     = "PASS",
      observed   = if (enc_class == "single_byte")
        sprintf("'%s' is a single-byte encoding; every byte sequence is valid by construction.",
                info$used)
      else
        sprintf("File is valid %s.", info$used),
      threshold  = sprintf("declared: %s", info$declared),
      message    = "File encoding matches the configuration."
    )))
  }

  # Validity is unknown: the UTF-8 scan itself failed (e.g. out of memory on a
  # very large delivery). Not a clean PASS -- the file was read as declared with
  # no verification -- and not a definitive FAIL either, so WARN.
  if (is.na(info$valid)) {
    return(list(dq_result(
      check_id   = "QC-16",
      check_name = "File encoding",
      status     = "WARN",
      observed   = sprintf("Could not verify %s: %s", info$used,
                           info$scan_error %||% "the encoding scan did not complete"),
      threshold  = sprintf("declared: %s", info$declared),
      message    = paste0("File encoding could not be verified; the file was ",
                          "read as declared without a validity scan.")
    )))
  }

  list()   # unreachable: valid is TRUE/FALSE/NA, all handled above
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
  expected <- config[["expected_columns"]]
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
#' Runs the full QC check suite (QC-01 to QC-16, SC-01, SC-02) against a
#' single data frame snapshot.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#' @param file_path Character or \code{NULL}. Absolute path to the file, used
#'   for the optional \code{max_file_size_mb} check in QC-14.
#' @param types Optional named character vector of pre-resolved column types;
#'   see \code{\link{check_inferred_types}}. When \code{NULL} (the default),
#'   types are resolved once here and shared by all type-dependent checks.
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
run_qc_checks <- function(df, config, file_path = NULL, types = NULL) {
  types <- types %||% resolve_col_types(df, config)
  c(
    check_file_encoding(df, config),
    check_missing_rate(df, config),
    check_empty_column(df, config),
    check_duplicate_rows(df, config),
    check_row_count(df, config),
    check_col_count(df, config),
    check_inferred_types(df, config, types = types),
    check_numeric_stats(df, config, types = types),
    check_distinct_counts(df, config, types = types),
    check_allowed_values(df, config),
    check_numeric_bounds(df, config),
    check_non_numeric(df, config, types = types),
    check_key_uniqueness(df, config),
    check_pattern(df, config),
    check_min_row_count(df, config, file_path = file_path),
    check_outliers(df, config, types = types),
    check_schema_contract(df, config)
  )
}
