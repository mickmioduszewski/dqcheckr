#' Compute missing rate for a vector
#' @keywords internal
#' @noRd
.missing_rate_vec <- function(x) mean(is.na(x) | x == "")

#' CP-01: Compare row count between deliveries
#' @keywords internal
#' @noRd
compare_row_count <- function(df_current, df_previous, config) {
  threshold  <- config$rules$max_row_count_change_pct %||% 0.10
  n_curr     <- nrow(df_current)
  n_prev     <- nrow(df_previous)
  pct_change <- (n_curr - n_prev) / n_prev
  status     <- if (abs(pct_change) > threshold) "WARN" else "PASS"
  list(dq_result(
    check_id   = "CP-01",
    check_name = "Row count change",
    status     = status,
    observed   = sprintf("%d rows (previous: %d; change: %+.1f%%)",
                         n_curr, n_prev, pct_change * 100),
    threshold  = sprintf("+/-%.0f%%", threshold * 100),
    message    = if (status == "WARN")
      sprintf("Row count changed by %+.1f%%, exceeding the %+.0f%% threshold.",
              pct_change * 100, threshold * 100)
    else
      sprintf("Row count change of %+.1f%% is within threshold.", pct_change * 100)
  ))
}

#' CP-02a/b/c: Detect schema differences between deliveries
#'
#' Returns three separate \code{\link{dq_result}} objects:
#' CP-02a (new columns), CP-02b (dropped columns), CP-02c (type changes).
#' The result list carries attributes \code{new_cols}, \code{dropped_cols},
#' and \code{type_changed_cols} for use by \code{\link{write_snapshot}}.
#'
#' @keywords internal
#' @noRd
compare_schema <- function(df_current, df_previous, config) {
  flag_new   <- isTRUE(config$rules$flag_new_columns     %||% TRUE)
  flag_drop  <- isTRUE(config$rules$flag_dropped_columns %||% TRUE)
  flag_type  <- isTRUE(config$rules$flag_type_changes    %||% TRUE)

  new_cols     <- setdiff(names(df_current),  names(df_previous))
  dropped_cols <- setdiff(names(df_previous), names(df_current))
  common_cols  <- intersect(names(df_current), names(df_previous))

  type_changed_cols <- character(0)
  for (col in common_cols) {
    t_curr <- resolve_col_type(col, df_current[[col]],  config)
    t_prev <- resolve_col_type(col, df_previous[[col]], config)
    if (t_curr != t_prev)
      type_changed_cols <- c(type_changed_cols,
                             sprintf("%s (%s -> %s)", col, t_prev, t_curr))
  }

  # CP-02a: new columns
  reported_new <- if (flag_new) new_cols else character(0)
  status_a <- if (length(reported_new) > 0) "WARN" else "PASS"
  res_a <- dq_result(
    check_id   = "CP-02a",
    check_name = "New columns",
    status     = status_a,
    observed   = if (length(reported_new) > 0)
      paste("New:", .cap_values(reported_new))
    else
      "None.",
    message    = if (length(reported_new) > 0)
      sprintf("%d new column(s) vs previous: %s.",
              length(reported_new), .cap_values(reported_new))
    else
      "No new columns vs previous delivery."
  )

  # CP-02b: dropped columns
  reported_drop <- if (flag_drop) dropped_cols else character(0)
  status_b <- if (length(reported_drop) > 0) "WARN" else "PASS"
  res_b <- dq_result(
    check_id   = "CP-02b",
    check_name = "Dropped columns",
    status     = status_b,
    observed   = if (length(reported_drop) > 0)
      paste("Dropped:", .cap_values(reported_drop))
    else
      "None.",
    message    = if (length(reported_drop) > 0)
      sprintf("%d dropped column(s) vs previous: %s.",
              length(reported_drop), .cap_values(reported_drop))
    else
      "No dropped columns vs previous delivery."
  )

  # CP-02c: type changes
  reported_type <- if (flag_type) type_changed_cols else character(0)
  status_c <- if (length(reported_type) > 0) "WARN" else "PASS"
  res_c <- dq_result(
    check_id   = "CP-02c",
    check_name = "Column type changes",
    status     = status_c,
    observed   = if (length(reported_type) > 0)
      paste("Type changes:", .cap_values(reported_type))
    else
      "None.",
    message    = if (length(reported_type) > 0)
      sprintf("%d column(s) changed type vs previous: %s.",
              length(reported_type), .cap_values(reported_type))
    else
      "No column type changes vs previous delivery."
  )

  result_list <- list(res_a, res_b, res_c)
  attr(result_list, "new_cols")          <- new_cols
  attr(result_list, "dropped_cols")      <- dropped_cols
  attr(result_list, "type_changed_cols") <- type_changed_cols
  result_list
}

#' CP-03: Compare per-column missing rate between deliveries
#' @keywords internal
#' @noRd
compare_missing_rate <- function(df_current, df_previous, config) {
  max_change_pp <- config$rules$max_missing_rate_change_pp %||% 2.0
  severity      <- tolower(config$rules$missing_rate_change_severity %||% "warn")
  breach_status <- if (severity == "fail") "FAIL" else "WARN"
  common_cols   <- intersect(names(df_current), names(df_previous))
  lapply(common_cols, function(col) {
    rate_curr <- .missing_rate_vec(df_current[[col]])
    rate_prev <- .missing_rate_vec(df_previous[[col]])
    change_pp <- (rate_curr - rate_prev) * 100
    status    <- if (change_pp > max_change_pp) breach_status else "PASS"
    dq_result(
      check_id   = "CP-03",
      check_name = "Missing rate change",
      column     = col,
      status     = status,
      observed   = sprintf("%.1f%% (previous: %.1f%%; change: %+.1f pp)",
                           rate_curr * 100, rate_prev * 100, change_pp),
      threshold  = sprintf("+%.1f pp", max_change_pp),
      message    = if (status != "PASS")
        sprintf("Column '%s' missing rate increased by %.1f pp, exceeding threshold.", col, change_pp)
      else
        sprintf("Column '%s' missing rate change is within threshold.", col)
    )
  })
}

#' CP-04: Compare numeric column means between deliveries
#' @keywords internal
#' @noRd
compare_numeric_mean <- function(df_current, df_previous, config) {
  threshold   <- config$rules$max_numeric_mean_shift_pct %||% 0.20
  common_cols <- intersect(names(df_current), names(df_previous))
  results     <- list()
  for (col in common_cols) {
    if (resolve_col_type(col, df_current[[col]],  config) != "numeric") next
    if (resolve_col_type(col, df_previous[[col]], config) != "numeric") next
    mean_curr <- mean(suppressWarnings(as.numeric(df_current[[col]])),  na.rm = TRUE)
    mean_prev <- mean(suppressWarnings(as.numeric(df_previous[[col]])), na.rm = TRUE)
    if (is.nan(mean_prev) || mean_prev == 0) next
    shift_pct <- abs((mean_curr - mean_prev) / mean_prev)
    status    <- if (shift_pct > threshold) "WARN" else "PASS"
    results <- c(results, list(dq_result(
      check_id   = "CP-04",
      check_name = "Numeric mean shift",
      column     = col,
      status     = status,
      observed   = sprintf("mean: %.4g (previous: %.4g; change: %+.1f%%)",
                           mean_curr, mean_prev,
                           (mean_curr - mean_prev) / abs(mean_prev) * 100),
      threshold  = sprintf("+/-%.0f%%", threshold * 100),
      message    = if (status == "WARN")
        sprintf("Column '%s' mean shifted by %.1f%%, exceeding threshold.",
                col, shift_pct * 100)
      else
        sprintf("Column '%s' mean shift is within threshold.", col)
    )))
  }
  results
}

#' CP-05: Detect new distinct values in character columns
#' @keywords internal
#' @noRd
compare_new_values <- function(df_current, df_previous, config) {
  common_cols <- intersect(names(df_current), names(df_previous))
  results     <- list()
  for (col in common_cols) {
    if (resolve_col_type(col, df_current[[col]], config) != "character") next
    curr_vals <- unique(df_current[[col]][!is.na(df_current[[col]]) &
                                          df_current[[col]] != ""])
    prev_vals <- unique(df_previous[[col]][!is.na(df_previous[[col]]) &
                                           df_previous[[col]] != ""])
    new_vals  <- setdiff(curr_vals, prev_vals)
    results <- c(results, list(dq_result(
      check_id   = "CP-05",
      check_name = "New distinct values",
      column     = col,
      status     = "INFO",
      observed   = if (length(new_vals) > 0)
        paste("New values:", .cap_values(new_vals))
      else
        "No new values.",
      message    = sprintf("Column '%s': %d new distinct value(s) vs previous.",
                           col, length(new_vals))
    )))
  }
  results
}

#' CP-06: Detect dropped distinct values in character columns
#' @keywords internal
#' @noRd
compare_dropped_values <- function(df_current, df_previous, config) {
  common_cols <- intersect(names(df_current), names(df_previous))
  results     <- list()
  for (col in common_cols) {
    if (resolve_col_type(col, df_current[[col]], config) != "character") next
    curr_vals    <- unique(df_current[[col]][!is.na(df_current[[col]]) &
                                             df_current[[col]] != ""])
    prev_vals    <- unique(df_previous[[col]][!is.na(df_previous[[col]]) &
                                              df_previous[[col]] != ""])
    dropped_vals <- setdiff(prev_vals, curr_vals)
    results <- c(results, list(dq_result(
      check_id   = "CP-06",
      check_name = "Dropped distinct values",
      column     = col,
      status     = "INFO",
      observed   = if (length(dropped_vals) > 0)
        paste("Dropped values:", .cap_values(dropped_vals))
      else
        "No dropped values.",
      message    = sprintf("Column '%s': %d value(s) from previous not in current.",
                           col, length(dropped_vals))
    )))
  }
  results
}

#' CP-07: Compare non-numeric rate in numeric columns between deliveries
#' @keywords internal
#' @noRd
compare_non_numeric_rate <- function(df_current, df_previous, config) {
  threshold   <- config$rules$max_non_numeric_rate_change_pp %||% 1.0
  common_cols <- intersect(names(df_current), names(df_previous))
  results     <- list()
  for (col in common_cols) {
    t_curr <- resolve_col_type(col, df_current[[col]],  config)
    t_prev <- resolve_col_type(col, df_previous[[col]], config)
    if (!t_curr %in% c("numeric", "character") &&
        !t_prev %in% c("numeric", "character")) next
    if (t_curr == "character" && t_prev == "character") next

    .nn_rate <- function(x) {
      ne <- x[!is.na(x) & x != ""]
      if (length(ne) == 0) return(0)
      length(ne[is.na(suppressWarnings(as.numeric(ne)))]) / length(ne)
    }

    rate_curr <- .nn_rate(df_current[[col]])
    rate_prev <- .nn_rate(df_previous[[col]])
    change_pp <- (rate_curr - rate_prev) * 100

    # G-02: always emit a result (PASS when no increase)
    status <- if (change_pp > threshold) "WARN" else "PASS"
    results <- c(results, list(dq_result(
      check_id   = "CP-07",
      check_name = "Non-numeric rate change",
      column     = col,
      status     = status,
      observed   = sprintf("%.2f%% (previous: %.2f%%; change: %+.2f pp)",
                           rate_curr * 100, rate_prev * 100, change_pp),
      threshold  = sprintf("+%.1f pp", threshold),
      message    = if (status == "WARN")
        sprintf("Column '%s' non-numeric rate increased by %.2f pp.", col, change_pp)
      else
        sprintf("Column '%s' non-numeric rate change is within threshold.", col)
    )))
  }
  results
}

#' CP-08: Check column order consistency between deliveries
#' @keywords internal
#' @noRd
compare_column_order <- function(df_current, df_previous, config) {
  if (!isTRUE(config$rules$flag_column_order_change %||% TRUE)) return(list())
  fmt        <- tolower(config$format %||% "csv")
  curr_names <- names(df_current)
  prev_names <- names(df_previous)

  if (!identical(curr_names, prev_names)) {
    # C-02: column_order_severity overrides the format-based default
    sev_cfg <- tolower(config$rules$column_order_severity %||% "")
    status  <- if (nzchar(sev_cfg)) toupper(sev_cfg) else
                 if (fmt == "fwf") "FAIL" else "WARN"
    return(list(dq_result(
      check_id   = "CP-08",
      check_name = "Column order change",
      status     = status,
      observed   = sprintf("Current: [%s] | Previous: [%s]",
                           paste(curr_names, collapse = ", "),
                           paste(prev_names, collapse = ", ")),
      message    = if (fmt == "fwf" || status == "FAIL")
        "Column order has changed. This is an error for fixed-width files."
      else
        "Column order has changed vs previous delivery."
    )))
  }

  list(dq_result(
    check_id   = "CP-08",
    check_name = "Column order change",
    status     = "PASS",
    observed   = "Column order is unchanged.",
    message    = "Column order matches previous delivery."
  ))
}

#' Run all version comparison checks between two dataset snapshots
#'
#' Runs CP-01 to CP-08 comparing a current delivery against the previous one.
#'
#' @param df_current A data frame. The current delivery.
#' @param df_previous A data frame. The previous delivery.
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects. The list carries
#'   attributes \code{new_cols}, \code{dropped_cols}, and
#'   \code{type_changed_cols} (character vectors) for use by the snapshot
#'   writer.
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
run_comparison_checks <- function(df_current, df_previous, config) {
  schema_res   <- compare_schema(df_current, df_previous, config)
  new_cols          <- attr(schema_res, "new_cols")
  dropped_cols      <- attr(schema_res, "dropped_cols")
  type_changed_cols <- attr(schema_res, "type_changed_cols")

  results <- c(
    compare_row_count(df_current, df_previous, config),
    schema_res,
    compare_missing_rate(df_current, df_previous, config),
    compare_numeric_mean(df_current, df_previous, config),
    compare_new_values(df_current, df_previous, config),
    compare_dropped_values(df_current, df_previous, config),
    compare_non_numeric_rate(df_current, df_previous, config),
    compare_column_order(df_current, df_previous, config)
  )

  attr(results, "new_cols")          <- new_cols
  attr(results, "dropped_cols")      <- dropped_cols
  attr(results, "type_changed_cols") <- type_changed_cols
  results
}
