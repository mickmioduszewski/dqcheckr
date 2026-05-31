#' Test for missing or empty values
#' @keywords internal
#' @noRd
.missing_vals <- function(x) is.na(x) | x == ""

# DuckDB helpers ---------------------------------------------------------------

.duck_cols <- function(con, tbl) {
  DBI::dbGetQuery(con,
    sprintf("SELECT column_name FROM (DESCRIBE %s)",
            DBI::dbQuoteIdentifier(con, tbl)))$column_name
}

.duck_nrow <- function(con, tbl) {
  DBI::dbGetQuery(con,
    sprintf("SELECT COUNT(*) AS n FROM %s",
            DBI::dbQuoteIdentifier(con, tbl)))$n
}

.duck_miss <- function(con, tbl, col) {
  DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) AS cnt FROM %s WHERE %s IS NULL OR %s = ''",
    DBI::dbQuoteIdentifier(con, tbl),
    DBI::dbQuoteIdentifier(con, col),
    DBI::dbQuoteIdentifier(con, col)))$cnt
}

# QC functions -----------------------------------------------------------------

#' QC-01: Check missing rate per column
#'
#' Returns a \code{\link{dq_result}} per column flagging columns whose
#' proportion of missing or empty values exceeds \code{max_missing_rate}.
#'
#' @param df A data frame with all columns as character vectors, or a character
#'   table name when \code{con} is provided.
#' @param config Named list as returned by \code{\link{load_config}}.
#' @param con A DuckDB connection or \code{NULL} (default).
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
check_missing_rate <- function(df, config, con = NULL) {
  if (!is.null(con)) {
    cols <- .duck_cols(con, df)
    n    <- .duck_nrow(con, df)
    return(lapply(cols, function(col) {
      threshold     <- col_threshold(config, col, "max_missing_rate", 0.05)
      missing_count <- .duck_miss(con, df, col)
      missing_rate  <- missing_count / n
      status <- if (missing_rate > threshold) "FAIL" else "PASS"
      dq_result(
        check_id   = "QC-01", check_name = "Missing rate", column = col,
        status     = status,
        observed   = sprintf("%.1f%% missing (%d of %d)",
                             missing_rate * 100, missing_count, n),
        threshold  = sprintf("%.1f%%", threshold * 100),
        message    = if (status == "FAIL")
          sprintf("Column '%s' missing rate %.1f%% exceeds threshold %.1f%%.",
                  col, missing_rate * 100, threshold * 100)
        else sprintf("Column '%s' missing rate is within threshold.", col)
      )
    }))
  }
  lapply(names(df), function(col) {
    threshold     <- col_threshold(config, col, "max_missing_rate", 0.05)
    missing_count <- sum(.missing_vals(df[[col]]))
    missing_rate  <- missing_count / nrow(df)
    status <- if (missing_rate > threshold) "FAIL" else "PASS"
    dq_result(
      check_id   = "QC-01", check_name = "Missing rate", column = col,
      status     = status,
      observed   = sprintf("%.1f%% missing (%d of %d)",
                           missing_rate * 100, missing_count, nrow(df)),
      threshold  = sprintf("%.1f%%", threshold * 100),
      message    = if (status == "FAIL")
        sprintf("Column '%s' missing rate %.1f%% exceeds threshold %.1f%%.",
                col, missing_rate * 100, threshold * 100)
      else sprintf("Column '%s' missing rate is within threshold.", col)
    )
  })
}

#' QC-02: Check for entirely empty columns
#' @keywords internal
#' @noRd
check_empty_column <- function(df, config, con = NULL) {
  if (!is.null(con)) {
    cols <- .duck_cols(con, df)
    n    <- .duck_nrow(con, df)
    return(lapply(cols, function(col) {
      miss <- .duck_miss(con, df, col)
      is_empty <- (miss == n)
      dq_result(
        check_id = "QC-02", check_name = "Empty column", column = col,
        status   = if (is_empty) "FAIL" else "PASS",
        observed = if (is_empty) "100% empty" else "Not empty",
        message  = if (is_empty)
          sprintf("Column '%s' is entirely empty.", col)
        else sprintf("Column '%s' has at least one non-empty value.", col)
      )
    }))
  }
  lapply(names(df), function(col) {
    is_empty <- all(.missing_vals(df[[col]]))
    dq_result(
      check_id = "QC-02", check_name = "Empty column", column = col,
      status   = if (is_empty) "FAIL" else "PASS",
      observed = if (is_empty) "100% empty" else "Not empty",
      message  = if (is_empty)
        sprintf("Column '%s' is entirely empty.", col)
      else sprintf("Column '%s' has at least one non-empty value.", col)
    )
  })
}

#' QC-03: Check for fully-duplicate rows
#' @keywords internal
#' @noRd
check_duplicate_rows <- function(df, config, con = NULL) {
  if (!is.null(con)) {
    cols  <- .duck_cols(con, df)
    col_q <- paste(vapply(cols, function(c) DBI::dbQuoteIdentifier(con, c),
                          character(1)), collapse = ", ")
    n_dups <- DBI::dbGetQuery(con, sprintf(
      "SELECT COALESCE(SUM(cnt - 1), 0) AS n FROM
       (SELECT COUNT(*) AS cnt FROM %s GROUP BY %s) t WHERE cnt > 1",
      DBI::dbQuoteIdentifier(con, df), col_q))$n
    status <- if (n_dups > 0) "WARN" else "PASS"
    return(list(dq_result(
      check_id = "QC-03", check_name = "Duplicate rows", status = status,
      observed = sprintf("%d fully-duplicate row(s)", n_dups),
      message  = if (n_dups > 0)
        sprintf("%d row(s) are exact duplicates of another row.", n_dups)
      else "No fully-duplicate rows found."
    )))
  }
  n_dups <- sum(duplicated(df))
  status <- if (n_dups > 0) "WARN" else "PASS"
  list(dq_result(
    check_id = "QC-03", check_name = "Duplicate rows", status = status,
    observed = sprintf("%d fully-duplicate row(s)", n_dups),
    message  = if (n_dups > 0)
      sprintf("%d row(s) are exact duplicates of another row.", n_dups)
    else "No fully-duplicate rows found."
  ))
}

#' QC-04: Report row count
#' @keywords internal
#' @noRd
check_row_count <- function(df, config, con = NULL) {
  n <- if (!is.null(con)) .duck_nrow(con, df) else nrow(df)
  list(dq_result(
    check_id = "QC-04", check_name = "Row count", status = "INFO",
    observed = as.character(n),
    message  = sprintf("File contains %d rows.", n)
  ))
}

#' QC-05: Report column count
#' @keywords internal
#' @noRd
check_col_count <- function(df, config, con = NULL) {
  n <- if (!is.null(con)) length(.duck_cols(con, df)) else ncol(df)
  list(dq_result(
    check_id = "QC-05", check_name = "Column count", status = "INFO",
    observed = as.character(n),
    message  = sprintf("File contains %d columns.", n)
  ))
}

#' QC-06: Report inferred column types
#' @keywords internal
#' @noRd
check_inferred_types <- function(df, config, con = NULL) {
  if (!is.null(con)) {
    cols <- .duck_cols(con, df)
    return(lapply(cols, function(col) {
      vals <- DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 1000",
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, df)))$v
      overridden <- !is.null((config$column_types %||% list())[[col]])
      typ <- resolve_col_type(col, as.character(vals), config)
      dq_result(
        check_id = "QC-06", check_name = "Inferred type", column = col,
        status = "INFO", observed = typ,
        message = if (overridden)
          sprintf("Column '%s' type set to %s (overridden).", col, typ)
        else sprintf("Column '%s' inferred as %s.", col, typ)
      )
    }))
  }
  lapply(names(df), function(col) {
    overridden <- !is.null((config$column_types %||% list())[[col]])
    typ        <- resolve_col_type(col, df[[col]], config)
    dq_result(
      check_id = "QC-06", check_name = "Inferred type", column = col,
      status = "INFO", observed = typ,
      message = if (overridden)
        sprintf("Column '%s' type set to %s (overridden).", col, typ)
      else sprintf("Column '%s' inferred as %s.", col, typ)
    )
  })
}

#' QC-07: Report numeric summary statistics
#' @keywords internal
#' @noRd
#' @importFrom stats sd
check_numeric_stats <- function(df, config, con = NULL) {
  results <- list()
  if (!is.null(con)) {
    cols <- .duck_cols(con, df)
    for (col in cols) {
      vals <- DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 10000",
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, df)))$v
      if (resolve_col_type(col, as.character(vals), config) != "numeric") next
      stats <- DBI::dbGetQuery(con, sprintf(
        "SELECT AVG(TRY_CAST(%s AS DOUBLE)) AS mn,
                MAX(TRY_CAST(%s AS DOUBLE)) AS mx,
                MIN(TRY_CAST(%s AS DOUBLE)) AS mi,
                STDDEV(TRY_CAST(%s AS DOUBLE)) AS sd
         FROM %s",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, df)))
      if (is.na(stats$mn)) next
      results <- c(results, list(dq_result(
        check_id = "QC-07", check_name = "Numeric stats", column = col,
        status = "INFO",
        observed = sprintf("min=%.4g, max=%.4g, mean=%.4g, sd=%.4g",
                           stats$mi, stats$mx, stats$mn,
                           if (!is.na(stats$sd)) stats$sd else NA_real_),
        message = sprintf("Summary statistics for numeric column '%s'.", col)
      )))
    }
    return(results)
  }
  for (col in names(df)) {
    if (resolve_col_type(col, df[[col]], config) != "numeric") next
    vals <- suppressWarnings(as.numeric(df[[col]]))
    vals <- vals[!is.na(vals)]
    if (length(vals) == 0) next
    results <- c(results, list(dq_result(
      check_id = "QC-07", check_name = "Numeric stats", column = col,
      status = "INFO",
      observed = sprintf("min=%.4g, max=%.4g, mean=%.4g, sd=%.4g",
                         min(vals), max(vals), mean(vals),
                         if (length(vals) > 1) sd(vals) else NA_real_),
      message = sprintf("Summary statistics for numeric column '%s'.", col)
    )))
  }
  results
}

#' QC-08: Report distinct value counts for character columns
#' @keywords internal
#' @noRd
check_distinct_counts <- function(df, config, con = NULL) {
  results <- list()
  if (!is.null(con)) {
    cols <- .duck_cols(con, df)
    for (col in cols) {
      vals <- DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 10000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df)))$v
      if (resolve_col_type(col, as.character(vals), config) != "character") next
      n_distinct <- DBI::dbGetQuery(con, sprintf(
        "SELECT COUNT(DISTINCT %s) AS n FROM %s WHERE %s IS NOT NULL AND %s <> ''",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col)))$n
      results <- c(results, list(dq_result(
        check_id = "QC-08", check_name = "Distinct value count", column = col,
        status = "INFO", observed = as.character(n_distinct),
        message = sprintf("Column '%s' has %d distinct non-empty value(s).", col, n_distinct)
      )))
    }
    return(results)
  }
  for (col in names(df)) {
    if (resolve_col_type(col, df[[col]], config) != "character") next
    n_distinct <- length(unique(df[[col]][!.missing_vals(df[[col]])]))
    results <- c(results, list(dq_result(
      check_id = "QC-08", check_name = "Distinct value count", column = col,
      status = "INFO", observed = as.character(n_distinct),
      message = sprintf("Column '%s' has %d distinct non-empty value(s).", col, n_distinct)
    )))
  }
  results
}

#' QC-09: Check for values outside the allowed set
#' @keywords internal
#' @noRd
check_allowed_values <- function(df, config, con = NULL) {
  results <- list()
  col_rules <- config$column_rules %||% list()
  for (col in names(col_rules)) {
    allowed <- col_rules[[col]]$allowed_values
    if (is.null(allowed)) next
    if (!is.null(con)) {
      if (!col %in% .duck_cols(con, df)) next
      vals_in <- paste(
        DBI::dbQuoteLiteral(con, allowed), collapse = ", ")
      bad <- DBI::dbGetQuery(con, sprintf(
        "SELECT DISTINCT %s AS v FROM %s
         WHERE %s IS NOT NULL AND %s <> '' AND %s NOT IN (%s)",
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, df),
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col),
        vals_in))$v
      status <- if (length(bad) > 0) "FAIL" else "PASS"
      results <- c(results, list(dq_result(
        check_id = "QC-09", check_name = "Allowed values", column = col,
        status = status,
        observed = if (length(bad) > 0)
          paste("Unexpected values:", .cap_values(bad))
        else "All values are in the allowed list.",
        threshold = paste("Allowed:", paste(allowed, collapse = ", ")),
        message = if (length(bad) > 0)
          sprintf("Column '%s' contains %d unexpected value(s): %s.",
                  col, length(bad), .cap_values(bad))
        else sprintf("Column '%s' contains only allowed values.", col)
      )))
      next
    }
    if (!col %in% names(df)) next
    vals <- df[[col]][!.missing_vals(df[[col]])]
    bad  <- setdiff(unique(vals), allowed)
    status <- if (length(bad) > 0) "FAIL" else "PASS"
    results <- c(results, list(dq_result(
      check_id = "QC-09", check_name = "Allowed values", column = col,
      status = status,
      observed = if (length(bad) > 0)
        paste("Unexpected values:", .cap_values(bad))
      else "All values are in the allowed list.",
      threshold = paste("Allowed:", paste(allowed, collapse = ", ")),
      message = if (length(bad) > 0)
        sprintf("Column '%s' contains %d unexpected value(s): %s.",
                col, length(bad), .cap_values(bad))
      else sprintf("Column '%s' contains only allowed values.", col)
    )))
  }
  results
}

#' QC-10: Check for out-of-range numeric values
#' @keywords internal
#' @noRd
#' @importFrom utils head
check_numeric_bounds <- function(df, config, con = NULL) {
  results <- list()
  col_rules <- config$column_rules %||% list()
  for (col in names(col_rules)) {
    min_val <- col_rules[[col]]$min_value
    max_val <- col_rules[[col]]$max_value
    if (is.null(min_val) && is.null(max_val)) next
    if (!is.null(con)) {
      if (!col %in% .duck_cols(con, df)) next
      conditions <- c(
        if (!is.null(min_val)) sprintf("TRY_CAST(%s AS DOUBLE) < %s",
                                       DBI::dbQuoteIdentifier(con, col), min_val),
        if (!is.null(max_val)) sprintf("TRY_CAST(%s AS DOUBLE) > %s",
                                       DBI::dbQuoteIdentifier(con, col), max_val)
      )
      violate <- DBI::dbGetQuery(con, sprintf(
        "SELECT DISTINCT %s AS v FROM %s WHERE %s IS NOT NULL AND %s <> '' AND (%s)",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
        paste(conditions, collapse = " OR ")))$v
      thr_parts <- c(if (!is.null(min_val)) paste("min:", min_val),
                     if (!is.null(max_val)) paste("max:", max_val))
      status <- if (length(violate) > 0) "FAIL" else "PASS"
      results <- c(results, list(dq_result(
        check_id = "QC-10", check_name = "Numeric bounds", column = col,
        status = status,
        observed = if (length(violate) > 0)
          paste("Out-of-range values:", paste(head(violate, 5), collapse = ", "))
        else "All values are within bounds.",
        threshold = paste(thr_parts, collapse = "; "),
        message = if (length(violate) > 0)
          sprintf("Column '%s' has %d out-of-range value(s).", col, length(violate))
        else sprintf("Column '%s' values are all within bounds.", col)
      )))
      next
    }
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
    thr_parts <- c(if (!is.null(min_val)) paste("min:", min_val),
                   if (!is.null(max_val)) paste("max:", max_val))
    results <- c(results, list(dq_result(
      check_id = "QC-10", check_name = "Numeric bounds", column = col,
      status = status,
      observed = if (length(violate) > 0)
        paste("Out-of-range values:", paste(head(violate, 5), collapse = ", "))
      else "All values are within bounds.",
      threshold = paste(thr_parts, collapse = "; "),
      message = if (length(violate) > 0)
        sprintf("Column '%s' has %d out-of-range value(s).", col, length(violate))
      else sprintf("Column '%s' values are all within bounds.", col)
    )))
  }
  results
}

#' QC-11: Check non-numeric rate in numeric columns
#' @keywords internal
#' @noRd
check_non_numeric <- function(df, config, con = NULL) {
  results <- list()
  if (!is.null(con)) {
    cols <- .duck_cols(con, df)
    for (col in cols) {
      vals <- DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 10000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df)))$v
      if (resolve_col_type(col, as.character(vals), config) != "numeric") next
      stats <- DBI::dbGetQuery(con, sprintf(
        "SELECT
           COUNT(*) FILTER (WHERE %s IS NOT NULL AND %s <> '') AS non_empty,
           COUNT(*) FILTER (WHERE %s IS NOT NULL AND %s <> ''
                            AND TRY_CAST(%s AS DOUBLE) IS NULL) AS bad
         FROM %s",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, df)))
      if (stats$non_empty == 0) next
      fail_threshold <- col_threshold(config, col, "max_non_numeric_rate", 0.01)
      warn_threshold <- col_threshold(config, col, "warn_non_numeric_rate", 0.0)
      rate   <- stats$bad / stats$non_empty
      status <- if (rate > fail_threshold) "FAIL" else if (rate > warn_threshold) "WARN" else "PASS"
      results <- c(results, list(dq_result(
        check_id = "QC-11", check_name = "Non-numeric values", column = col,
        status = status,
        observed = sprintf("%d non-numeric value(s) (%.2f%%)", stats$bad, rate * 100),
        threshold = sprintf("WARN > %.2f%%, FAIL > %.2f%%",
                            warn_threshold * 100, fail_threshold * 100),
        message = switch(status,
          FAIL = sprintf("Column '%s' non-numeric rate %.2f%% exceeds fail threshold %.2f%%.",
                         col, rate * 100, fail_threshold * 100),
          WARN = sprintf("Column '%s' non-numeric rate %.2f%% exceeds warn threshold %.2f%%.",
                         col, rate * 100, warn_threshold * 100),
          PASS = sprintf("Column '%s' has no non-numeric values above warn threshold.", col)
        )
      )))
    }
    return(results)
  }
  for (col in names(df)) {
    if (resolve_col_type(col, df[[col]], config) != "numeric") next
    non_empty <- df[[col]][!.missing_vals(df[[col]])]
    if (length(non_empty) == 0) next
    fail_threshold <- col_threshold(config, col, "max_non_numeric_rate", 0.01)
    warn_threshold <- col_threshold(config, col, "warn_non_numeric_rate", 0.0)
    bad      <- non_empty[is.na(suppressWarnings(as.numeric(non_empty)))]
    rate     <- length(bad) / length(non_empty)
    status   <- if (rate > fail_threshold) "FAIL" else if (rate > warn_threshold) "WARN" else "PASS"
    results <- c(results, list(dq_result(
      check_id = "QC-11", check_name = "Non-numeric values", column = col,
      status = status,
      observed = sprintf("%d non-numeric value(s) (%.2f%%)", length(bad), rate * 100),
      threshold = sprintf("WARN > %.2f%%, FAIL > %.2f%%",
                          warn_threshold * 100, fail_threshold * 100),
      message = switch(status,
        FAIL = sprintf("Column '%s' non-numeric rate %.2f%% exceeds fail threshold %.2f%%.",
                       col, rate * 100, fail_threshold * 100),
        WARN = sprintf("Column '%s' non-numeric rate %.2f%% exceeds warn threshold %.2f%%.",
                       col, rate * 100, warn_threshold * 100),
        PASS = sprintf("Column '%s' has no non-numeric values above warn threshold.", col)
      )
    )))
  }
  results
}

#' QC-12: Check uniqueness of key columns
#' @keywords internal
#' @noRd
check_key_uniqueness <- function(df, config, con = NULL) {
  keys <- config$key_columns
  if (is.null(keys) || length(keys) == 0) return(list())

  if (is.character(keys) && length(keys) == 1) keys <- list(keys)

  is_composite <- is.list(keys) && length(keys) > 1 &&
    all(vapply(keys, is.character, logical(1)))

  if (is_composite) {
    col_list <- unlist(keys)
    if (!is.null(con)) {
      avail  <- .duck_cols(con, df)
      missing_cols <- setdiff(col_list, avail)
    } else {
      missing_cols <- setdiff(col_list, names(df))
    }
    if (length(missing_cols) > 0) {
      return(lapply(missing_cols, function(col) dq_result(
        check_id = "QC-12", check_name = "Key uniqueness", column = col,
        status = "FAIL", observed = "Column not found in file",
        message = sprintf("Key column '%s' is not present in the file.", col)
      )))
    }
    if (!is.null(con)) {
      col_q  <- paste(vapply(col_list, function(c)
        DBI::dbQuoteIdentifier(con, c), character(1)), collapse = ", ")
      n_dups <- DBI::dbGetQuery(con, sprintf(
        "SELECT COALESCE(SUM(cnt - 1), 0) AS n FROM
         (SELECT COUNT(*) AS cnt FROM %s GROUP BY %s) t WHERE cnt > 1",
        DBI::dbQuoteIdentifier(con, df), col_q))$n
    } else {
      n_dups <- sum(duplicated(df[, col_list, drop = FALSE]))
    }
    key_label <- paste(col_list, collapse = "+")
    status <- if (n_dups > 0) "FAIL" else "PASS"
    return(list(dq_result(
      check_id = "QC-12", check_name = "Key uniqueness", column = key_label,
      status = status,
      observed = sprintf("%d duplicate composite key(s) found", n_dups),
      message = if (n_dups > 0)
        sprintf("Composite key [%s] has %d duplicate(s).", key_label, n_dups)
      else sprintf("Composite key [%s] has all unique values.", key_label)
    )))
  }

  lapply(if (is.list(keys)) unlist(keys) else keys, function(col) {
    if (!is.null(con)) {
      if (!col %in% .duck_cols(con, df)) {
        return(dq_result(
          check_id = "QC-12", check_name = "Key uniqueness", column = col,
          status = "FAIL", observed = "Column not found in file",
          message = sprintf("Key column '%s' is not present in the file.", col)
        ))
      }
      n_dups <- DBI::dbGetQuery(con, sprintf(
        "SELECT COALESCE(SUM(cnt - 1), 0) AS n FROM
         (SELECT COUNT(*) AS cnt FROM %s GROUP BY %s) t WHERE cnt > 1",
        DBI::dbQuoteIdentifier(con, df),
        DBI::dbQuoteIdentifier(con, col)))$n
    } else {
      if (!col %in% names(df)) {
        return(dq_result(
          check_id = "QC-12", check_name = "Key uniqueness", column = col,
          status = "FAIL", observed = "Column not found in file",
          message = sprintf("Key column '%s' is not present in the file.", col)
        ))
      }
      n_dups <- sum(duplicated(df[[col]]))
    }
    status <- if (n_dups > 0) "FAIL" else "PASS"
    dq_result(
      check_id = "QC-12", check_name = "Key uniqueness", column = col,
      status = status,
      observed = sprintf("%d duplicate value(s) found", n_dups),
      message = if (n_dups > 0)
        sprintf("Key column '%s' has %d duplicate value(s).", col, n_dups)
      else sprintf("Key column '%s' has all unique values.", col)
    )
  })
}

#' QC-13: Check values against a regex pattern
#' @keywords internal
#' @noRd
check_pattern <- function(df, config, con = NULL) {
  results   <- list()
  col_rules <- config$column_rules %||% list()
  for (col in names(col_rules)) {
    pattern <- col_rules[[col]]$pattern
    if (is.null(pattern)) next
    if (!is.null(con)) {
      if (!col %in% .duck_cols(con, df)) next
      bad_count <- DBI::dbGetQuery(con, sprintf(
        "SELECT COUNT(*) AS n FROM %s
         WHERE %s IS NOT NULL AND %s <> ''
           AND NOT regexp_matches(%s, %s)",
        DBI::dbQuoteIdentifier(con, df),
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteLiteral(con, pattern)))$n
      status <- if (bad_count > 0) "FAIL" else "PASS"
      results <- c(results, list(dq_result(
        check_id = "QC-13", check_name = "Pattern / regex", column = col,
        status = status,
        observed = sprintf("%d value(s) do not match pattern", bad_count),
        threshold = pattern,
        message = if (bad_count > 0)
          sprintf("Column '%s': %d value(s) violate pattern '%s'.", col, bad_count, pattern)
        else sprintf("Column '%s': all values match pattern '%s'.", col, pattern)
      )))
      next
    }
    if (!col %in% names(df)) next
    non_empty  <- df[[col]][!.missing_vals(df[[col]])]
    bad_count  <- sum(!grepl(pattern, non_empty, perl = TRUE))
    status     <- if (bad_count > 0) "FAIL" else "PASS"
    results <- c(results, list(dq_result(
      check_id = "QC-13", check_name = "Pattern / regex", column = col,
      status = status,
      observed = sprintf("%d value(s) do not match pattern", bad_count),
      threshold = pattern,
      message = if (bad_count > 0)
        sprintf("Column '%s': %d value(s) violate pattern '%s'.", col, bad_count, pattern)
      else sprintf("Column '%s': all values match pattern '%s'.", col, pattern)
    )))
  }
  results
}

#' QC-14: Check minimum and maximum row count thresholds
#' @keywords internal
#' @noRd
check_min_row_count <- function(df, config, con = NULL) {
  n      <- if (!is.null(con)) .duck_nrow(con, df) else nrow(df)
  min_rc <- table_threshold(config, "min_row_count", 0)
  max_rc <- table_threshold(config, "max_row_count", Inf)
  results <- list()

  if (min_rc > 0) {
    status <- if (n < min_rc) "FAIL" else "PASS"
    results <- c(results, list(dq_result(
      check_id = "QC-14", check_name = "Minimum row count", status = status,
      observed = sprintf("%d rows", n), threshold = sprintf("%d rows minimum", min_rc),
      message = if (status == "FAIL")
        sprintf("File has %d rows, below the minimum of %d.", n, min_rc)
      else sprintf("File has %d rows, meeting the minimum of %d.", n, min_rc)
    )))
  } else {
    results <- c(results, list(dq_result(
      check_id = "QC-14", check_name = "Minimum row count", status = "PASS",
      observed = as.character(n),
      message = "Minimum row count check is disabled (min_row_count = 0)."
    )))
  }

  if (is.finite(max_rc)) {
    status <- if (n > max_rc) "FAIL" else "PASS"
    results <- c(results, list(dq_result(
      check_id = "QC-14b", check_name = "Maximum row count", status = status,
      observed = sprintf("%d rows", n), threshold = sprintf("%d rows maximum", max_rc),
      message = if (status == "FAIL")
        sprintf("File has %d rows, exceeding the maximum of %d.", n, max_rc)
      else sprintf("File has %d rows, within the maximum of %d.", n, max_rc)
    )))
  }

  results
}

#' Check file size against configured maximum
#' @keywords internal
#' @noRd
check_file_size <- function(file_path, config) {
  max_mb <- table_threshold(config, "max_file_size_mb", Inf)
  size_b <- file.info(file_path)$size
  size_mb <- size_b / 1e6
  if (is.finite(max_mb) && size_mb > max_mb) {
    list(dq_result(
      check_id = "QC-15", check_name = "File size", status = "FAIL",
      observed = sprintf("%.3f MB", size_mb),
      threshold = sprintf("%.3f MB maximum", max_mb),
      message = sprintf("File size %.3f MB exceeds maximum %.3f MB.", size_mb, max_mb)
    ))
  } else {
    list(dq_result(
      check_id = "QC-15", check_name = "File size", status = "INFO",
      observed = sprintf("%.3f MB", size_mb),
      message = sprintf("File size is %.3f MB.", size_mb)
    ))
  }
}

#' SC-01/SC-02: Check columns against expected schema contract
#' @keywords internal
#' @noRd
check_schema_contract <- function(df, config, con = NULL) {
  expected <- config$expected_columns
  if (is.null(expected)) return(list())

  actual <- if (!is.null(con)) .duck_cols(con, df) else names(df)
  results <- list()

  extra <- setdiff(actual, expected)
  if (length(extra) > 0) {
    for (col in extra) {
      results <- c(results, list(dq_result(
        check_id = "SC-01", check_name = "Unexpected column", column = col,
        status = "FAIL",
        observed = sprintf("Column '%s' is not in the expected schema.", col),
        message = sprintf("Column '%s' is present in the file but not in expected_columns.", col)
      )))
    }
  } else {
    results <- c(results, list(dq_result(
      check_id = "SC-01", check_name = "Unexpected column", status = "PASS",
      observed = "No unexpected columns.",
      message = "All file columns are in the expected schema."
    )))
  }

  missing_cols <- setdiff(expected, actual)
  if (length(missing_cols) > 0) {
    for (col in missing_cols) {
      results <- c(results, list(dq_result(
        check_id = "SC-02", check_name = "Missing expected column", column = col,
        status = "FAIL",
        observed = sprintf("Expected column '%s' is absent.", col),
        message = sprintf("Column '%s' is in expected_columns but absent from the file.", col)
      )))
    }
  } else {
    results <- c(results, list(dq_result(
      check_id = "SC-02", check_name = "Missing expected column", status = "PASS",
      observed = "All expected columns are present.",
      message = "No expected columns are missing from the file."
    )))
  }

  results
}

#' Outlier detection check
#' @keywords internal
#' @noRd
check_outliers <- function(df, config, con = NULL) {
  results <- list()
  if (!is.null(con)) {
    cols <- .duck_cols(con, df)
    for (col in cols) {
      max_z <- col_threshold(config, col, "max_z_score", Inf)
      if (!is.finite(max_z)) next
      vals <- DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 10000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df)))$v
      if (resolve_col_type(col, as.character(vals), config) != "numeric") next
      outliers <- DBI::dbGetQuery(con, sprintf(
        "SELECT COUNT(*) AS n FROM (
           SELECT ABS((TRY_CAST(%s AS DOUBLE) -
                  AVG(TRY_CAST(%s AS DOUBLE)) OVER()) /
                  NULLIF(STDDEV(TRY_CAST(%s AS DOUBLE)) OVER(), 0)) AS z
           FROM %s
           WHERE TRY_CAST(%s AS DOUBLE) IS NOT NULL
         ) t WHERE z > %s",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df),
        DBI::dbQuoteIdentifier(con, col), max_z))$n
      status <- if (outliers > 0) "FAIL" else "PASS"
      results <- c(results, list(dq_result(
        check_id = "QC-16", check_name = "Outlier detection", column = col,
        status = status,
        observed = sprintf("%d value(s) with |Z| > %.1f", outliers, max_z),
        threshold = sprintf("|Z| <= %.1f", max_z),
        message = if (status == "FAIL")
          sprintf("Column '%s': %d outlier(s) with |Z| > %.1f.", col, outliers, max_z)
        else sprintf("Column '%s': no outliers above Z threshold.", col)
      )))
    }
    return(results)
  }
  for (col in names(df)) {
    max_z <- col_threshold(config, col, "max_z_score", Inf)
    if (!is.finite(max_z)) next
    if (resolve_col_type(col, df[[col]], config) != "numeric") next
    vals <- suppressWarnings(as.numeric(df[[col]]))
    vals <- vals[!is.na(vals)]
    if (length(vals) < 2) next
    z_scores <- abs(as.numeric(base::scale(vals)))
    outliers <- sum(z_scores > max_z, na.rm = TRUE)
    status <- if (outliers > 0) "FAIL" else "PASS"
    results <- c(results, list(dq_result(
      check_id = "QC-16", check_name = "Outlier detection", column = col,
      status = status,
      observed = sprintf("%d value(s) with |Z| > %.1f", outliers, max_z),
      threshold = sprintf("|Z| <= %.1f", max_z),
      message = if (status == "FAIL")
        sprintf("Column '%s': %d outlier(s) with |Z| > %.1f.", col, outliers, max_z)
      else sprintf("Column '%s': no outliers above Z threshold.", col)
    )))
  }
  results
}

#' Run all generic quality checks on a dataset
#'
#' Runs the full QC check suite (QC-01 to QC-16, SC-01, SC-02) against a
#' single dataset snapshot.
#'
#' @param df A data frame with all columns as character vectors (as returned by
#'   \code{\link{read_dataset}}), or a DuckDB table name when \code{con} is
#'   provided.
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#' @param file_path Character. Path to the source file; used for the
#'   \code{max_file_size_mb} check. Pass \code{NULL} to skip the size check.
#' @param con A DuckDB connection or \code{NULL} (default). When provided,
#'   check execution uses DuckDB SQL.
#'
#' @return A list of \code{\link{dq_result}} objects.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg     <- load_config("starwars_csv", config_dir = cfg_dir)
#' path    <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df      <- read_dataset(path, cfg)
#' results <- run_qc_checks(df, cfg, file_path = path)
#'
#' @export
run_qc_checks <- function(df, config, file_path = NULL, con = NULL) {
  results <- c(
    check_missing_rate(df, config, con),
    check_empty_column(df, config, con),
    check_duplicate_rows(df, config, con),
    check_row_count(df, config, con),
    check_col_count(df, config, con),
    check_inferred_types(df, config, con),
    check_numeric_stats(df, config, con),
    check_distinct_counts(df, config, con),
    check_allowed_values(df, config, con),
    check_numeric_bounds(df, config, con),
    check_non_numeric(df, config, con),
    check_key_uniqueness(df, config, con),
    check_pattern(df, config, con),
    check_min_row_count(df, config, con),
    check_schema_contract(df, config, con),
    check_outliers(df, config, con)
  )
  if (!is.null(file_path) && file.exists(file_path)) {
    results <- c(results, check_file_size(file_path, config))
  }
  results
}
