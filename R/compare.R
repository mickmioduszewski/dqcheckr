#' Compute missing rate for a vector
#' @keywords internal
.missing_rate_vec <- function(x) mean(is.na(x) | x == "")

#' CP-01: Compare row count between deliveries
#' @keywords internal
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

#' CP-02: Detect schema differences between deliveries
#' @keywords internal
compare_schema <- function(df_current, df_previous, config) {
  type_threshold <- config$rules$type_inference_threshold %||% 0.90
  flag_new   <- isTRUE(config$rules$flag_new_columns     %||% TRUE)
  flag_drop  <- isTRUE(config$rules$flag_dropped_columns %||% TRUE)
  flag_type  <- isTRUE(config$rules$flag_type_changes    %||% TRUE)

  new_cols     <- setdiff(names(df_current), names(df_previous))
  dropped_cols <- setdiff(names(df_previous), names(df_current))
  common_cols  <- intersect(names(df_current), names(df_previous))

  type_changes <- character(0)
  for (col in common_cols) {
    t_curr <- infer_col_type(df_current[[col]], type_threshold)
    t_prev <- infer_col_type(df_previous[[col]], type_threshold)
    if (t_curr != t_prev) {
      type_changes <- c(type_changes,
                        sprintf("%s (%s -> %s)", col, t_prev, t_curr))
    }
  }

  # Flags control what is reported; actual changes are always tracked for SQLite
  reported_new  <- if (flag_new)  new_cols     else character(0)
  reported_drop <- if (flag_drop) dropped_cols else character(0)
  reported_type <- if (flag_type) type_changes else character(0)

  has_change <- length(reported_new) > 0 || length(reported_drop) > 0 ||
    length(reported_type) > 0
  status <- if (has_change) "WARN" else "PASS"

  parts <- c(
    if (length(reported_new) > 0)
      paste("New columns:", paste(reported_new, collapse = ", ")),
    if (length(reported_drop) > 0)
      paste("Dropped columns:", paste(reported_drop, collapse = ", ")),
    if (length(reported_type) > 0)
      paste("Type changes:", paste(reported_type, collapse = "; "))
  )
  observed <- if (length(parts) > 0) paste(parts, collapse = ". ") else "No schema changes."

  result_list <- list(dq_result(
    check_id   = "CP-02",
    check_name = "Schema diff",
    status     = status,
    observed   = observed,
    message    = if (has_change)
      "Schema differences detected vs previous delivery."
    else
      "Schema is identical to previous delivery."
  ))

  attr(result_list, "new_cols")     <- new_cols
  attr(result_list, "dropped_cols") <- dropped_cols
  result_list
}

#' CP-03: Compare per-column missing rate between deliveries
#' @keywords internal
compare_missing_rate <- function(df_current, df_previous, config) {
  max_change_pp <- config$rules$max_missing_rate_change_pp %||% 2.0
  common_cols   <- intersect(names(df_current), names(df_previous))
  lapply(common_cols, function(col) {
    rate_curr <- .missing_rate_vec(df_current[[col]])
    rate_prev <- .missing_rate_vec(df_previous[[col]])
    change_pp <- (rate_curr - rate_prev) * 100
    status    <- if (change_pp > max_change_pp) "WARN" else "PASS"
    dq_result(
      check_id   = "CP-03",
      check_name = "Missing rate change",
      column     = col,
      status     = status,
      observed   = sprintf("%.1f%% (previous: %.1f%%; change: %+.1f pp)",
                           rate_curr * 100, rate_prev * 100, change_pp),
      threshold  = sprintf("+%.1f pp", max_change_pp),
      message    = if (status == "WARN")
        sprintf("Column '%s' missing rate increased by %.1f pp, exceeding threshold.", col, change_pp)
      else
        sprintf("Column '%s' missing rate change is within threshold.", col)
    )
  })
}

#' CP-04: Compare numeric column means between deliveries
#' @keywords internal
compare_numeric_mean <- function(df_current, df_previous, config) {
  threshold      <- config$rules$max_numeric_mean_shift_pct %||% 0.20
  type_threshold <- config$rules$type_inference_threshold %||% 0.90
  common_cols <- intersect(names(df_current), names(df_previous))
  results     <- list()
  for (col in common_cols) {
    if (infer_col_type(df_current[[col]],  type_threshold) != "numeric") next
    if (infer_col_type(df_previous[[col]], type_threshold) != "numeric") next
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
compare_new_values <- function(df_current, df_previous, config) {
  type_threshold <- config$rules$type_inference_threshold %||% 0.90
  common_cols <- intersect(names(df_current), names(df_previous))
  results     <- list()
  for (col in common_cols) {
    if (infer_col_type(df_current[[col]], type_threshold) != "character") next
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
        paste("New values:", paste(new_vals, collapse = ", "))
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
compare_dropped_values <- function(df_current, df_previous, config) {
  type_threshold <- config$rules$type_inference_threshold %||% 0.90
  common_cols <- intersect(names(df_current), names(df_previous))
  results     <- list()
  for (col in common_cols) {
    if (infer_col_type(df_current[[col]], type_threshold) != "character") next
    curr_vals     <- unique(df_current[[col]][!is.na(df_current[[col]]) &
                                              df_current[[col]] != ""])
    prev_vals     <- unique(df_previous[[col]][!is.na(df_previous[[col]]) &
                                               df_previous[[col]] != ""])
    dropped_vals  <- setdiff(prev_vals, curr_vals)
    results <- c(results, list(dq_result(
      check_id   = "CP-06",
      check_name = "Dropped distinct values",
      column     = col,
      status     = "INFO",
      observed   = if (length(dropped_vals) > 0)
        paste("Dropped values:", paste(dropped_vals, collapse = ", "))
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
compare_non_numeric_rate <- function(df_current, df_previous, config) {
  threshold      <- config$rules$max_non_numeric_rate_change_pp %||% 1.0
  type_threshold <- config$rules$type_inference_threshold %||% 0.90
  common_cols <- intersect(names(df_current), names(df_previous))
  results     <- list()
  for (col in common_cols) {
    t_curr <- infer_col_type(df_current[[col]], type_threshold)
    t_prev <- infer_col_type(df_previous[[col]], type_threshold)
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
    if (change_pp <= 0) next

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
compare_column_order <- function(df_current, df_previous, config) {
  if (!isTRUE(config$rules$flag_column_order_change %||% TRUE)) return(list())
  fmt        <- tolower(config$format %||% "csv")
  curr_names <- names(df_current)
  prev_names <- names(df_previous)

  if (!identical(curr_names, prev_names)) {
    status <- if (fmt == "fwf") "FAIL" else "WARN"
    return(list(dq_result(
      check_id   = "CP-08",
      check_name = "Column order change",
      status     = status,
      observed   = sprintf("Current: [%s] | Previous: [%s]",
                           paste(curr_names, collapse = ", "),
                           paste(prev_names, collapse = ", ")),
      message    = if (fmt == "fwf")
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
#'   attributes \code{new_cols} and \code{dropped_cols} (character vectors)
#'   for use by the snapshot writer.
#'
#' @examples
#' \dontrun{
#' cfg  <- load_config("my_dataset", "config")
#' curr <- read_dataset("data/current.csv", cfg)
#' prev <- read_dataset("data/previous.csv", cfg)
#' results <- run_comparison_checks(curr, prev, cfg)
#' }
#'
#' @export
run_comparison_checks <- function(df_current, df_previous, config) {
  c(
    compare_row_count(df_current, df_previous, config),
    compare_schema(df_current, df_previous, config),
    compare_missing_rate(df_current, df_previous, config),
    compare_numeric_mean(df_current, df_previous, config),
    compare_new_values(df_current, df_previous, config),
    compare_dropped_values(df_current, df_previous, config),
    compare_non_numeric_rate(df_current, df_previous, config),
    compare_column_order(df_current, df_previous, config)
  )
}
