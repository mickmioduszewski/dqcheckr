base_config <- function(overrides = list()) {
  cfg <- list(
    format = "csv",
    rules = list(
      max_missing_rate               = 0.05,
      max_non_numeric_rate           = 0.01,
      min_row_count                  = 0,
      max_row_count_change_pct       = 0.10,
      max_numeric_mean_shift_pct     = 0.20,
      max_missing_rate_change_pp     = 2.0,
      max_non_numeric_rate_change_pp = 1.0
    ),
    column_rules     = list(),
    key_columns      = NULL,
    expected_columns = NULL
  )
  utils::modifyList(cfg, overrides)
}

make_accounts_df <- function() {
  data.frame(
    id              = c("ID001", "ID002", "ID003", "ID004", "ID005"),
    name            = c("Alice", "Bob", "Clara", "David", "Emma"),
    country_code    = c("GB", "US", "DE", "FR", "GB"),
    account_status  = c("ACTIVE", "ACTIVE", "CLOSED", "ACTIVE", "SUSPENDED"),
    account_balance = c("15000", "8500", "0", "250000", "1200"),
    created_date    = c("2024-01-15", "2024-02-20", "2023-11-01",
                        "2024-03-10", "2024-04-05"),
    stringsAsFactors = FALSE
  )
}

make_snapshot_df <- function() {
  data.frame(
    id              = paste0("ID00", 1:5),
    account_balance = c("15000", "8500", "0", "250000", "1200"),
    stringsAsFactors = FALSE
  )
}
