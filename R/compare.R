#' Compute missing rate for a vector
#' @keywords internal
#' @noRd
.missing_rate_vec <- function(x) mean(is.na(x) | x == "")

# DuckDB helper for compare functions ------------------------------------------

.duck_miss_rate <- function(con, tbl, col) {
  res <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) FILTER (WHERE %s IS NULL OR %s = '') AS miss,
            COUNT(*) AS total
     FROM %s",
    DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
    DBI::dbQuoteIdentifier(con, tbl)))
  if (res$total == 0) return(0)
  res$miss / res$total
}

.duck_nn_rate <- function(con, tbl, col) {
  res <- DBI::dbGetQuery(con, sprintf(
    "SELECT COUNT(*) FILTER (WHERE %s IS NOT NULL AND %s <> '') AS non_empty,
            COUNT(*) FILTER (WHERE %s IS NOT NULL AND %s <> ''
                             AND TRY_CAST(%s AS DOUBLE) IS NULL) AS bad
     FROM %s",
    DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
    DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
    DBI::dbQuoteIdentifier(con, col),
    DBI::dbQuoteIdentifier(con, tbl)))
  if (res$non_empty == 0) return(0)
  res$bad / res$non_empty
}

# CP functions -----------------------------------------------------------------

#' CP-01: Compare row count between deliveries
#' @keywords internal
#' @noRd
compare_row_count <- function(df_current, df_previous, config, con = NULL) {
  threshold <- config$rules$max_row_count_change_pct %||% 0.10
  if (!is.null(con)) {
    n_curr <- .duck_nrow(con, df_current)
    n_prev <- .duck_nrow(con, df_previous)
  } else {
    n_curr <- nrow(df_current)
    n_prev <- nrow(df_previous)
  }
  pct_change <- (n_curr - n_prev) / n_prev
  status     <- if (abs(pct_change) > threshold) "WARN" else "PASS"
  list(dq_result(
    check_id = "CP-01", check_name = "Row count change", status = status,
    observed = sprintf("%d rows (previous: %d; change: %+.1f%%)",
                       n_curr, n_prev, pct_change * 100),
    threshold = sprintf("+/-%.0f%%", threshold * 100),
    message = if (status == "WARN")
      sprintf("Row count changed by %+.1f%%, exceeding the %+.0f%% threshold.",
              pct_change * 100, threshold * 100)
    else sprintf("Row count change of %+.1f%% is within threshold.", pct_change * 100)
  ))
}

#' CP-02a/b/c: Detect schema differences between deliveries
#' @keywords internal
#' @noRd
compare_schema <- function(df_current, df_previous, config, con = NULL) {
  flag_new   <- isTRUE(config$rules$flag_new_columns     %||% TRUE)
  flag_drop  <- isTRUE(config$rules$flag_dropped_columns %||% TRUE)
  flag_type  <- isTRUE(config$rules$flag_type_changes    %||% TRUE)

  curr_names <- if (!is.null(con)) .duck_cols(con, df_current)  else names(df_current)
  prev_names <- if (!is.null(con)) .duck_cols(con, df_previous) else names(df_previous)

  new_cols     <- setdiff(curr_names, prev_names)
  dropped_cols <- setdiff(prev_names, curr_names)
  common_cols  <- intersect(curr_names, prev_names)

  type_changed <- character(0)
  for (col in common_cols) {
    if (!is.null(con)) {
      curr_vals <- DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 1000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_current)))$v
      prev_vals <- DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 1000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_previous)))$v
      t_curr <- resolve_col_type(col, as.character(curr_vals), config)
      t_prev <- resolve_col_type(col, as.character(prev_vals), config)
    } else {
      t_curr <- resolve_col_type(col, df_current[[col]],  config)
      t_prev <- resolve_col_type(col, df_previous[[col]], config)
    }
    if (t_curr != t_prev)
      type_changed <- c(type_changed, sprintf("%s (%s -> %s)", col, t_prev, t_curr))
  }

  # CP-02a — new columns
  new_status   <- if (flag_new && length(new_cols) > 0) "WARN" else "PASS"
  new_reported <- flag_new && length(new_cols) > 0
  r_02a <- dq_result(
    check_id = "CP-02a", check_name = "Schema diff: new columns",
    status = new_status,
    observed = if (new_reported)
      paste("New columns:", paste(new_cols, collapse = ", "))
    else "No new columns.",
    message = if (new_reported)
      paste("New column(s) detected:", paste(new_cols, collapse = ", "))
    else "No new columns vs previous delivery."
  )

  # CP-02b — dropped columns
  drop_status   <- if (flag_drop && length(dropped_cols) > 0) "WARN" else "PASS"
  drop_reported <- flag_drop && length(dropped_cols) > 0
  r_02b <- dq_result(
    check_id = "CP-02b", check_name = "Schema diff: dropped columns",
    status = drop_status,
    observed = if (drop_reported)
      paste("Dropped columns:", paste(dropped_cols, collapse = ", "))
    else "No dropped columns.",
    message = if (drop_reported)
      paste("Dropped column(s) detected:", paste(dropped_cols, collapse = ", "))
    else "No dropped columns vs previous delivery."
  )

  # CP-02c — type changes
  type_status   <- if (flag_type && length(type_changed) > 0) "WARN" else "PASS"
  type_reported <- flag_type && length(type_changed) > 0
  r_02c <- dq_result(
    check_id = "CP-02c", check_name = "Schema diff: type changes",
    status = type_status,
    observed = if (type_reported)
      paste("Type changes:", paste(type_changed, collapse = "; "))
    else "No type changes.",
    message = if (type_reported)
      paste("Type change(s) detected:", paste(type_changed, collapse = "; "))
    else "No type changes vs previous delivery."
  )

  result_list <- list(r_02a, r_02b, r_02c)

  attr(result_list, "new_cols")     <- new_cols
  attr(result_list, "dropped_cols") <- dropped_cols
  attr(result_list, "type_changed") <- type_changed
  result_list
}

#' CP-03: Compare per-column missing rate between deliveries
#' @keywords internal
#' @noRd
compare_missing_rate <- function(df_current, df_previous, config, con = NULL) {
  curr_names <- if (!is.null(con)) .duck_cols(con, df_current)  else names(df_current)
  prev_names <- if (!is.null(con)) .duck_cols(con, df_previous) else names(df_previous)
  common_cols <- intersect(curr_names, prev_names)
  lapply(common_cols, function(col) {
    max_change_pp <- col_threshold(config, col, "max_missing_rate_change_pp", 2.0)
    sev           <- config$rules$missing_rate_change_severity %||% "warn"
    if (!is.null(con)) {
      rate_curr <- .duck_miss_rate(con, df_current,  col)
      rate_prev <- .duck_miss_rate(con, df_previous, col)
    } else {
      rate_curr <- .missing_rate_vec(df_current[[col]])
      rate_prev <- .missing_rate_vec(df_previous[[col]])
    }
    change_pp <- (rate_curr - rate_prev) * 100
    status    <- if (change_pp > max_change_pp) toupper(sev) else "PASS"
    dq_result(
      check_id = "CP-03", check_name = "Missing rate change", column = col,
      status = status,
      observed = sprintf("%.1f%% (previous: %.1f%%; change: %+.1f pp)",
                         rate_curr * 100, rate_prev * 100, change_pp),
      threshold = sprintf("+%.1f pp", max_change_pp),
      message = if (status != "PASS")
        sprintf("Column '%s' missing rate increased by %.1f pp, exceeding threshold.", col, change_pp)
      else sprintf("Column '%s' missing rate change is within threshold.", col)
    )
  })
}

#' CP-04: Compare numeric column means between deliveries
#' @keywords internal
#' @noRd
compare_numeric_mean <- function(df_current, df_previous, config, con = NULL) {
  curr_names <- if (!is.null(con)) .duck_cols(con, df_current)  else names(df_current)
  prev_names <- if (!is.null(con)) .duck_cols(con, df_previous) else names(df_previous)
  common_cols <- intersect(curr_names, prev_names)
  results <- list()
  for (col in common_cols) {
    if (!is.null(con)) {
      curr_samp <- as.character(DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 1000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_current)))$v)
      prev_samp <- as.character(DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 1000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_previous)))$v)
    } else {
      curr_samp <- df_current[[col]]
      prev_samp <- df_previous[[col]]
    }
    if (resolve_col_type(col, curr_samp, config) != "numeric") next
    if (resolve_col_type(col, prev_samp, config) != "numeric") next
    threshold <- col_threshold(config, col, "max_numeric_mean_shift_pct", 0.20)
    if (!is.null(con)) {
      mean_curr <- DBI::dbGetQuery(con, sprintf(
        "SELECT AVG(TRY_CAST(%s AS DOUBLE)) AS m FROM %s",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_current)))$m
      mean_prev <- DBI::dbGetQuery(con, sprintf(
        "SELECT AVG(TRY_CAST(%s AS DOUBLE)) AS m FROM %s",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_previous)))$m
    } else {
      mean_curr <- mean(suppressWarnings(as.numeric(df_current[[col]])),  na.rm = TRUE)
      mean_prev <- mean(suppressWarnings(as.numeric(df_previous[[col]])), na.rm = TRUE)
    }
    if (is.na(mean_prev) || is.nan(mean_prev) || mean_prev == 0) next
    shift_pct <- abs((mean_curr - mean_prev) / mean_prev)
    status    <- if (shift_pct > threshold) "WARN" else "PASS"
    results <- c(results, list(dq_result(
      check_id = "CP-04", check_name = "Numeric mean shift", column = col,
      status = status,
      observed = sprintf("mean: %.4g (previous: %.4g; change: %+.1f%%)",
                         mean_curr, mean_prev,
                         (mean_curr - mean_prev) / abs(mean_prev) * 100),
      threshold = sprintf("+/-%.0f%%", threshold * 100),
      message = if (status == "WARN")
        sprintf("Column '%s' mean shifted by %.1f%%, exceeding threshold.", col, shift_pct * 100)
      else sprintf("Column '%s' mean shift is within threshold.", col)
    )))
  }
  results
}

#' CP-05: Detect new distinct values in character columns
#' @keywords internal
#' @noRd
compare_new_values <- function(df_current, df_previous, config, con = NULL) {
  curr_names <- if (!is.null(con)) .duck_cols(con, df_current)  else names(df_current)
  prev_names <- if (!is.null(con)) .duck_cols(con, df_previous) else names(df_previous)
  common_cols <- intersect(curr_names, prev_names)
  results <- list()
  for (col in common_cols) {
    if (!is.null(con)) {
      samp <- as.character(DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 1000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_current)))$v)
    } else {
      samp <- df_current[[col]]
    }
    if (resolve_col_type(col, samp, config) != "character") next
    if (!is.null(con)) {
      new_vals <- DBI::dbGetQuery(con, sprintf(
        "SELECT DISTINCT %s AS v FROM %s
         WHERE %s IS NOT NULL AND %s <> ''
           AND %s NOT IN (SELECT DISTINCT %s FROM %s WHERE %s IS NOT NULL AND %s <> '')",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_current),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_previous),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col)))$v
    } else {
      curr_vals <- unique(df_current[[col]][!is.na(df_current[[col]]) &
                                            df_current[[col]] != ""])
      prev_vals <- unique(df_previous[[col]][!is.na(df_previous[[col]]) &
                                             df_previous[[col]] != ""])
      new_vals  <- setdiff(curr_vals, prev_vals)
    }
    results <- c(results, list(dq_result(
      check_id = "CP-05", check_name = "New distinct values", column = col,
      status = "INFO",
      observed = if (length(new_vals) > 0)
        paste("New values:", .cap_values(new_vals))
      else "No new values.",
      message = sprintf("Column '%s': %d new distinct value(s) vs previous.",
                        col, length(new_vals))
    )))
  }
  results
}

#' CP-06: Detect dropped distinct values in character columns
#' @keywords internal
#' @noRd
compare_dropped_values <- function(df_current, df_previous, config, con = NULL) {
  curr_names <- if (!is.null(con)) .duck_cols(con, df_current)  else names(df_current)
  prev_names <- if (!is.null(con)) .duck_cols(con, df_previous) else names(df_previous)
  common_cols <- intersect(curr_names, prev_names)
  results <- list()
  for (col in common_cols) {
    if (!is.null(con)) {
      samp <- as.character(DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 1000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_current)))$v)
    } else {
      samp <- df_current[[col]]
    }
    if (resolve_col_type(col, samp, config) != "character") next
    if (!is.null(con)) {
      dropped_vals <- DBI::dbGetQuery(con, sprintf(
        "SELECT DISTINCT %s AS v FROM %s
         WHERE %s IS NOT NULL AND %s <> ''
           AND %s NOT IN (SELECT DISTINCT %s FROM %s WHERE %s IS NOT NULL AND %s <> '')",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_previous),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_current),
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, col)))$v
    } else {
      curr_vals    <- unique(df_current[[col]][!is.na(df_current[[col]]) &
                                              df_current[[col]] != ""])
      prev_vals    <- unique(df_previous[[col]][!is.na(df_previous[[col]]) &
                                               df_previous[[col]] != ""])
      dropped_vals <- setdiff(prev_vals, curr_vals)
    }
    results <- c(results, list(dq_result(
      check_id = "CP-06", check_name = "Dropped distinct values", column = col,
      status = "INFO",
      observed = if (length(dropped_vals) > 0)
        paste("Dropped values:", .cap_values(dropped_vals))
      else "No dropped values.",
      message = sprintf("Column '%s': %d value(s) from previous not in current.",
                        col, length(dropped_vals))
    )))
  }
  results
}

#' CP-07: Compare non-numeric rate in numeric columns between deliveries
#' @keywords internal
#' @noRd
compare_non_numeric_rate <- function(df_current, df_previous, config, con = NULL) {
  curr_names <- if (!is.null(con)) .duck_cols(con, df_current)  else names(df_current)
  prev_names <- if (!is.null(con)) .duck_cols(con, df_previous) else names(df_previous)
  common_cols <- intersect(curr_names, prev_names)
  results <- list()
  for (col in common_cols) {
    if (!is.null(con)) {
      curr_samp <- as.character(DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 1000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_current)))$v)
      prev_samp <- as.character(DBI::dbGetQuery(con, sprintf(
        "SELECT %s AS v FROM %s LIMIT 1000",
        DBI::dbQuoteIdentifier(con, col), DBI::dbQuoteIdentifier(con, df_previous)))$v)
    } else {
      curr_samp <- df_current[[col]]
      prev_samp <- df_previous[[col]]
    }
    t_curr <- resolve_col_type(col, curr_samp, config)
    t_prev <- resolve_col_type(col, prev_samp, config)
    if (!t_curr %in% c("numeric", "character") &&
        !t_prev %in% c("numeric", "character")) next
    if (t_curr == "character" && t_prev == "character") next

    threshold <- col_threshold(config, col, "max_non_numeric_rate_change_pp", 1.0)

    if (!is.null(con)) {
      rate_curr <- .duck_nn_rate(con, df_current,  col)
      rate_prev <- .duck_nn_rate(con, df_previous, col)
    } else {
      .nn_rate <- function(x) {
        ne <- x[!is.na(x) & x != ""]
        if (length(ne) == 0) return(0)
        length(ne[is.na(suppressWarnings(as.numeric(ne)))]) / length(ne)
      }
      rate_curr <- .nn_rate(df_current[[col]])
      rate_prev <- .nn_rate(df_previous[[col]])
    }
    change_pp <- (rate_curr - rate_prev) * 100
    status    <- if (change_pp > threshold) "WARN" else "PASS"
    results <- c(results, list(dq_result(
      check_id = "CP-07", check_name = "Non-numeric rate change", column = col,
      status = status,
      observed = sprintf("%.2f%% (previous: %.2f%%; change: %+.2f pp)",
                         rate_curr * 100, rate_prev * 100, change_pp),
      threshold = sprintf("+%.1f pp", threshold),
      message = if (status == "WARN")
        sprintf("Column '%s' non-numeric rate increased by %.2f pp.", col, change_pp)
      else sprintf("Column '%s' non-numeric rate change is within threshold.", col)
    )))
  }
  results
}

#' CP-08: Check column order consistency between deliveries
#' @keywords internal
#' @noRd
compare_column_order <- function(df_current, df_previous, config, con = NULL) {
  if (!isTRUE(config$rules$flag_column_order_change %||% TRUE)) return(list())
  fmt        <- tolower(config$format %||% "csv")
  curr_names <- if (!is.null(con)) .duck_cols(con, df_current)  else names(df_current)
  prev_names <- if (!is.null(con)) .duck_cols(con, df_previous) else names(df_previous)

  if (!identical(curr_names, prev_names)) {
    fmt_default <- if (fmt == "fwf") "fail" else "warn"
    sev_key     <- tolower(config$rules$column_order_severity %||% fmt_default)
    status      <- toupper(sev_key)
    return(list(dq_result(
      check_id = "CP-08", check_name = "Column order change", status = status,
      observed = sprintf("Current: [%s] | Previous: [%s]",
                         paste(curr_names, collapse = ", "),
                         paste(prev_names, collapse = ", ")),
      message = if (status == "FAIL")
        "Column order has changed. This is an error (column_order_severity = fail)."
      else "Column order has changed vs previous delivery."
    )))
  }

  list(dq_result(
    check_id = "CP-08", check_name = "Column order change", status = "PASS",
    observed = "Column order is unchanged.",
    message  = "Column order matches previous delivery."
  ))
}

#' Run all version comparison checks between two dataset snapshots
#'
#' Runs CP-01 to CP-08 comparing a current delivery against the previous one.
#'
#' @param df_current A data frame or DuckDB table name. The current delivery.
#' @param df_previous A data frame or DuckDB table name. The previous delivery.
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#' @param con A DuckDB connection or \code{NULL} (default).
#'
#' @return A list of \code{\link{dq_result}} objects. The list carries
#'   attributes \code{new_cols} and \code{dropped_cols} (character vectors)
#'   for use by the snapshot writer.
#'
#' @examples
#' cfg_dir   <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg       <- load_config("starwars_csv", config_dir = cfg_dir)
#' curr_path <- system.file("demonstrations/data2/starwars_v2.csv", package = "dqcheckr")
#' prev_path <- system.file("demonstrations/data2/starwars_v1.csv", package = "dqcheckr")
#' curr      <- read_dataset(curr_path, cfg)
#' prev      <- read_dataset(prev_path, cfg)
#' results   <- run_comparison_checks(curr, prev, cfg)
#'
#' @export
run_comparison_checks <- function(df_current, df_previous, config, con = NULL) {
  schema_res   <- compare_schema(df_current, df_previous, config, con)
  new_cols     <- attr(schema_res, "new_cols")
  dropped_cols <- attr(schema_res, "dropped_cols")
  type_changed <- attr(schema_res, "type_changed")

  results <- c(
    compare_row_count(df_current, df_previous, config, con),
    schema_res,
    compare_missing_rate(df_current, df_previous, config, con),
    compare_numeric_mean(df_current, df_previous, config, con),
    compare_new_values(df_current, df_previous, config, con),
    compare_dropped_values(df_current, df_previous, config, con),
    compare_non_numeric_rate(df_current, df_previous, config, con),
    compare_column_order(df_current, df_previous, config, con)
  )

  attr(results, "new_cols")     <- new_cols
  attr(results, "dropped_cols") <- dropped_cols
  attr(results, "type_changed") <- type_changed
  results
}
