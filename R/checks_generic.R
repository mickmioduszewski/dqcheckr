#' Test for missing or empty values
#' @keywords internal
.missing_vals <- function(x) is.na(x) | x == ""

#' QC-01: Check missing rate per column
#' @keywords internal
check_missing_rate <- function(df, config) {
  threshold <- config$rules$max_missing_rate %||% 0.05
  lapply(names(df), function(col) {
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
#' @keywords internal
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
#' @keywords internal
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
#' @keywords internal
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
#' @keywords internal
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
#' @keywords internal
check_inferred_types <- function(df, config) {
  lapply(names(df), function(col) {
    typ <- infer_col_type(df[[col]])
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
#' @keywords internal
#' @importFrom stats sd
check_numeric_stats <- function(df, config) {
  results <- list()
  for (col in names(df)) {
    if (infer_col_type(df[[col]]) != "numeric") next
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
#' @keywords internal
check_distinct_counts <- function(df, config) {
  results <- list()
  for (col in names(df)) {
    if (infer_col_type(df[[col]]) != "character") next
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
#' @keywords internal
check_allowed_values <- function(df, config) {
  results <- list()
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
        paste("Unexpected values:", paste(bad, collapse = ", "))
      else
        "All values are in the allowed list.",
      threshold  = paste("Allowed:", paste(allowed, collapse = ", ")),
      message    = if (length(bad) > 0)
        sprintf("Column '%s' contains %d unexpected value(s): %s.",
                col, length(bad), paste(bad, collapse = ", "))
      else
        sprintf("Column '%s' contains only allowed values.", col)
    )))
  }
  results
}

#' QC-10: Check for out-of-range numeric values
#' @keywords internal
#' @importFrom utils head
check_numeric_bounds <- function(df, config) {
  results <- list()
  col_rules <- config$column_rules %||% list()
  for (col in names(col_rules)) {
    min_val <- col_rules[[col]]$min_value
    max_val <- col_rules[[col]]$max_value
    if (is.null(min_val) && is.null(max_val)) next
    if (!col %in% names(df)) next
    vals    <- suppressWarnings(as.numeric(df[[col]]))
    violate <- character(0)
    if (!is.null(min_val)) {
      below <- df[[col]][!is.na(vals) & vals < min_val]
      violate <- c(violate, unique(below))
    }
    if (!is.null(max_val)) {
      above <- df[[col]][!is.na(vals) & vals > max_val]
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
#' @keywords internal
check_non_numeric <- function(df, config) {
  threshold <- config$rules$max_non_numeric_rate %||% 0.01
  results   <- list()
  for (col in names(df)) {
    if (infer_col_type(df[[col]]) != "numeric") next
    non_empty <- df[[col]][!.missing_vals(df[[col]])]
    if (length(non_empty) == 0) next
    bad      <- non_empty[is.na(suppressWarnings(as.numeric(non_empty)))]
    rate     <- length(bad) / length(non_empty)
    status   <- if (rate > threshold) "FAIL" else if (length(bad) > 0) "WARN" else "PASS"
    results <- c(results, list(dq_result(
      check_id   = "QC-11",
      check_name = "Non-numeric values",
      column     = col,
      status     = status,
      observed   = sprintf("%d non-numeric value(s) (%.2f%%)",
                           length(bad), rate * 100),
      threshold  = sprintf("%.2f%%", threshold * 100),
      message    = switch(status,
        FAIL = sprintf("Column '%s' non-numeric rate %.2f%% exceeds threshold %.2f%%.",
                       col, rate * 100, threshold * 100),
        WARN = sprintf("Column '%s' has %d non-numeric value(s) below threshold.",
                       col, length(bad)),
        PASS = sprintf("Column '%s' has no non-numeric values.", col)
      )
    )))
  }
  results
}

#' QC-12: Check uniqueness of key columns
#' @keywords internal
check_key_uniqueness <- function(df, config) {
  keys <- config$key_columns
  if (is.null(keys) || length(keys) == 0) return(list())
  lapply(keys, function(col) {
    if (!col %in% names(df)) {
      return(dq_result(
        check_id   = "QC-12",
        check_name = "Key uniqueness",
        column     = col,
        status     = "FAIL",
        observed   = "Column not found in file",
        message    = sprintf("Key column '%s' is not present in the file.", col)
      ))
    }
    n_dups <- sum(duplicated(df[[col]]))
    status <- if (n_dups > 0) "FAIL" else "PASS"
    dq_result(
      check_id   = "QC-12",
      check_name = "Key uniqueness",
      column     = col,
      status     = status,
      observed   = sprintf("%d duplicate value(s) found", n_dups),
      message    = if (n_dups > 0)
        sprintf("Key column '%s' has %d duplicate value(s).", col, n_dups)
      else
        sprintf("Key column '%s' has all unique values.", col)
    )
  })
}

#' QC-13: Check values against a regex pattern
#' @keywords internal
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

#' QC-14: Check minimum row count threshold
#' @keywords internal
check_min_row_count <- function(df, config) {
  min_rc <- config$rules$min_row_count %||% 0
  if (min_rc <= 0) {
    return(list(dq_result(
      check_id   = "QC-14",
      check_name = "Minimum row count",
      status     = "PASS",
      observed   = as.character(nrow(df)),
      message    = "Minimum row count check is disabled (min_row_count = 0)."
    )))
  }
  status <- if (nrow(df) < min_rc) "FAIL" else "PASS"
  list(dq_result(
    check_id   = "QC-14",
    check_name = "Minimum row count",
    status     = status,
    observed   = sprintf("%d rows", nrow(df)),
    threshold  = sprintf("%d rows minimum", min_rc),
    message    = if (status == "FAIL")
      sprintf("File has %d rows, below the minimum of %d.", nrow(df), min_rc)
    else
      sprintf("File has %d rows, meeting the minimum of %d.", nrow(df), min_rc)
  ))
}

#' SC-01/SC-02: Check columns against expected schema contract
#' @keywords internal
check_schema_contract <- function(df, config) {
  expected <- config$expected_columns
  if (is.null(expected)) return(list())

  results <- list()

  extra <- setdiff(names(df), expected)
  if (length(extra) > 0) {
    for (col in extra) {
      results <- c(results, list(dq_result(
        check_id   = "SC-01",
        check_name = "Unexpected column",
        column     = col,
        status     = "FAIL",
        observed   = sprintf("Column '%s' is not in the expected schema.", col),
        message    = sprintf("Column '%s' is present in the file but not in expected_columns.", col)
      )))
    }
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
    for (col in missing_cols) {
      results <- c(results, list(dq_result(
        check_id   = "SC-02",
        check_name = "Missing expected column",
        column     = col,
        status     = "FAIL",
        observed   = sprintf("Expected column '%s' is absent.", col),
        message    = sprintf("Column '%s' is in expected_columns but absent from the file.", col)
      )))
    }
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
#' Runs the full QC check suite (QC-01 to QC-14, SC-01, SC-02) against a
#' single data frame snapshot.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}).
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects.
#'
#' @examples
#' \dontrun{
#' cfg <- load_config("my_dataset", "config")
#' df  <- read_dataset("data/my_file.csv", cfg)
#' results <- run_qc_checks(df, cfg)
#' }
#'
#' @export
run_qc_checks <- function(df, config) {
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
    check_min_row_count(df, config),
    check_schema_contract(df, config)
  )
}
