library(testthat)
library(dqcheckr)

base_config <- function() {
  list(
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
}

make_curr <- function() {
  data.frame(
    id              = paste0("ID00", 1:5),
    name            = c("Alice", "Bob", "Clara", "David", "Emma"),
    country_code    = c("GB", "US", "DE", "FR", "GB"),
    account_status  = c("ACTIVE", "ACTIVE", "CLOSED", "ACTIVE", "SUSPENDED"),
    account_balance = c("15000", "8500", "0", "250000", "1200"),
    created_date    = c("2024-01-15", "2024-02-20", "2023-11-01",
                        "2024-03-10", "2024-04-05"),
    stringsAsFactors = FALSE
  )
}

make_prev <- function() {
  data.frame(
    id              = paste0("ID00", 1:5),
    name            = c("Alice", "Bob", "Clara", "David", "Emma"),
    country_code    = c("GB", "US", "DE", "FR", "GB"),
    account_status  = c("ACTIVE", "ACTIVE", "CLOSED", "ACTIVE", "SUSPENDED"),
    account_balance = c("14500", "8200", "0", "248000", "1100"),
    created_date    = c("2024-01-15", "2024-02-20", "2023-11-01",
                        "2024-03-10", "2024-04-05"),
    stringsAsFactors = FALSE
  )
}

# -- CP-01 Row count change ----------------------------------------------------

test_that("compare_row_count() returns PASS when change is within threshold", {
  res <- compare_row_count(make_curr(), make_prev(), base_config())
  expect_equal(res[[1]]$status, "PASS")
})

test_that("compare_row_count() returns WARN when change exceeds threshold", {
  curr <- make_curr()[1:2, ]
  res  <- compare_row_count(curr, make_prev(), base_config())
  expect_equal(res[[1]]$status, "WARN")
})

# -- CP-02 Schema diff ---------------------------------------------------------

test_that("compare_schema() emits three result objects", {
  res <- compare_schema(make_curr(), make_prev(), base_config())
  ids <- vapply(res, \(r) r$check_id, character(1))
  expect_true("CP-02a" %in% ids)
  expect_true("CP-02b" %in% ids)
  expect_true("CP-02c" %in% ids)
})

test_that("compare_schema() returns all PASS when schemas are identical", {
  res <- compare_schema(make_curr(), make_prev(), base_config())
  statuses <- vapply(res, \(r) r$status, character(1))
  expect_true(all(statuses == "PASS"))
})

test_that("compare_schema() CP-02a WARN when current has new column", {
  curr       <- make_curr()
  curr$extra <- "x"
  res <- compare_schema(curr, make_prev(), base_config())
  r02a <- Filter(\(r) r$check_id == "CP-02a", res)
  expect_equal(r02a[[1]]$status, "WARN")
  expect_true("extra" %in% attr(res, "new_cols"))
})

test_that("compare_schema() CP-02b WARN when column is dropped", {
  curr <- make_curr()[, -3]
  res  <- compare_schema(curr, make_prev(), base_config())
  r02b <- Filter(\(r) r$check_id == "CP-02b", res)
  expect_equal(r02b[[1]]$status, "WARN")
  expect_true("country_code" %in% attr(res, "dropped_cols"))
})

test_that("compare_schema() CP-02c WARN on type change", {
  curr                 <- make_curr()
  curr$account_balance <- c("high", "low", "medium", "high", "low")
  res  <- compare_schema(curr, make_prev(), base_config())
  r02c <- Filter(\(r) r$check_id == "CP-02c", res)
  expect_equal(r02c[[1]]$status, "WARN")
})

test_that("compare_schema() emits PASS for each unchanged dimension", {
  # only new column — CP-02b and CP-02c should be PASS
  curr       <- make_curr()
  curr$extra <- "x"
  res  <- compare_schema(curr, make_prev(), base_config())
  r02b <- Filter(\(r) r$check_id == "CP-02b", res)
  r02c <- Filter(\(r) r$check_id == "CP-02c", res)
  expect_equal(r02b[[1]]$status, "PASS")
  expect_equal(r02c[[1]]$status, "PASS")
})

test_that("compare_schema() attaches new_cols and dropped_cols attributes", {
  curr       <- make_curr()
  curr$new1  <- "x"
  res <- compare_schema(curr, make_prev(), base_config())
  expect_false(is.null(attr(res, "new_cols")))
  expect_false(is.null(attr(res, "dropped_cols")))
})

# -- CP-03 Missing rate change -------------------------------------------------

test_that("compare_missing_rate() returns PASS when missing rate unchanged", {
  res <- compare_missing_rate(make_curr(), make_prev(), base_config())
  expect_true(all(vapply(res, \(r) r$status == "PASS", logical(1))))
})

test_that("compare_missing_rate() returns WARN when missing rate increases significantly", {
  curr       <- make_curr()
  curr$name  <- NA_character_
  res        <- compare_missing_rate(curr, make_prev(), base_config())
  name_r     <- Filter(\(r) r$column == "name", res)
  expect_equal(name_r[[1]]$status, "WARN")
})

test_that("compare_missing_rate() produces FAIL when missing_rate_change_severity = 'fail'", {
  curr      <- make_curr()
  curr$name <- NA_character_
  cfg       <- base_config()
  cfg$rules$missing_rate_change_severity  <- "fail"
  cfg$rules$max_missing_rate_change_pp    <- 1.0
  res    <- compare_missing_rate(curr, make_prev(), cfg)
  name_r <- Filter(\(r) r$column == "name", res)
  expect_equal(name_r[[1]]$status, "FAIL")
})

test_that("compare_missing_rate() produces WARN by default when threshold breached", {
  curr      <- make_curr()
  curr$name <- NA_character_
  res    <- compare_missing_rate(curr, make_prev(), base_config())
  name_r <- Filter(\(r) r$column == "name", res)
  expect_equal(name_r[[1]]$status, "WARN")
})

# -- CP-04 Numeric mean shift --------------------------------------------------

test_that("compare_numeric_mean() returns PASS when mean shift is small", {
  res <- compare_numeric_mean(make_curr(), make_prev(), base_config())
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "PASS")
})

test_that("compare_numeric_mean() returns WARN when mean shift exceeds threshold", {
  curr                 <- make_curr()
  curr$account_balance <- as.character(
    as.numeric(make_curr()$account_balance) * 10
  )
  res <- compare_numeric_mean(curr, make_prev(), base_config())
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "WARN")
})

# -- CP-05 New distinct values -------------------------------------------------

test_that("compare_new_values() returns INFO always", {
  res <- compare_new_values(make_curr(), make_prev(), base_config())
  expect_true(all(vapply(res, \(r) r$status == "INFO", logical(1))))
})

test_that("compare_new_values() reports new values in observed field", {
  curr                 <- make_curr()
  curr$country_code[1] <- "JP"
  res <- compare_new_values(curr, make_prev(), base_config())
  cc  <- Filter(\(r) r$column == "country_code", res)
  expect_match(cc[[1]]$observed, "JP")
})

# -- CP-06 Dropped distinct values --------------------------------------------

test_that("compare_dropped_values() returns INFO always", {
  res <- compare_dropped_values(make_curr(), make_prev(), base_config())
  expect_true(all(vapply(res, \(r) r$status == "INFO", logical(1))))
})

test_that("compare_new_values() caps observed string at 20 values", {
  curr <- data.frame(code = paste0("NEW", 1:25), stringsAsFactors = FALSE)
  prev <- data.frame(code = character(0),        stringsAsFactors = FALSE)
  cfg  <- base_config()
  cfg$column_types <- list(code = "character")
  res <- compare_new_values(curr, prev, cfg)
  expect_match(res[[1]]$observed, "and 5 more")
})

test_that("compare_dropped_values() caps observed string at 20 values", {
  prev <- data.frame(code = paste0("OLD", 1:25), stringsAsFactors = FALSE)
  curr <- data.frame(code = character(0),        stringsAsFactors = FALSE)
  cfg  <- base_config()
  cfg$column_types <- list(code = "character")
  res <- compare_dropped_values(curr, prev, cfg)
  expect_match(res[[1]]$observed, "and 5 more")
})

# -- CP-07 Non-numeric rate change ---------------------------------------------

test_that("compare_non_numeric_rate() returns PASS when rate unchanged", {
  res <- compare_non_numeric_rate(make_curr(), make_prev(), base_config())
  statuses <- vapply(res, `[[`, character(1), "status")
  expect_true(all(statuses %in% c("PASS", "INFO")))
})

test_that("compare_non_numeric_rate() returns WARN when rate increases significantly", {
  curr                 <- make_curr()
  curr$account_balance <- c("N/A", "unknown", "bad", "1000", "2000")
  res <- compare_non_numeric_rate(curr, make_prev(), base_config())
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "WARN")
})

test_that("compare_non_numeric_rate() emits PASS when rate has not increased", {
  res <- compare_non_numeric_rate(make_curr(), make_curr(), base_config())
  statuses <- vapply(res, `[[`, character(1), "status")
  expect_true(all(statuses == "PASS"))
})

test_that("compare_non_numeric_rate() emits one result per numeric column in both snapshots", {
  res <- compare_non_numeric_rate(make_curr(), make_prev(), base_config())
  cols <- vapply(res, `[[`, character(1), "column")
  expect_true("account_balance" %in% cols)
  expect_equal(length(res), length(Filter(\(c) c == "account_balance", cols)))
})

# -- CP-08 Column order --------------------------------------------------------

test_that("compare_column_order() returns PASS when column order unchanged", {
  res <- compare_column_order(make_curr(), make_prev(), base_config())
  expect_equal(res[[1]]$status, "PASS")
})

test_that("compare_column_order() returns WARN for CSV when order changes", {
  curr     <- make_curr()[, rev(names(make_curr()))]
  cfg      <- base_config()
  cfg$format <- "csv"
  res <- compare_column_order(curr, make_prev(), cfg)
  expect_equal(res[[1]]$status, "WARN")
})

test_that("compare_column_order() returns FAIL for FWF when order changes", {
  curr     <- make_curr()[, rev(names(make_curr()))]
  cfg      <- base_config()
  cfg$format <- "fwf"
  res <- compare_column_order(curr, make_prev(), cfg)
  expect_equal(res[[1]]$status, "FAIL")
})

test_that("compare_column_order() produces FAIL for CSV when column_order_severity = 'fail'", {
  curr <- make_curr()[, rev(names(make_curr()))]
  cfg  <- base_config()
  cfg$format <- "csv"
  cfg$rules$column_order_severity <- "fail"
  res <- compare_column_order(curr, make_prev(), cfg)
  expect_equal(res[[1]]$status, "FAIL")
})

test_that("compare_column_order() defaults to WARN for CSV when column_order_severity absent", {
  curr <- make_curr()[, rev(names(make_curr()))]
  cfg  <- base_config()
  cfg$format <- "csv"
  res <- compare_column_order(curr, make_prev(), cfg)
  expect_equal(res[[1]]$status, "WARN")
})

test_that("compare_column_order() defaults to FAIL for FWF when column_order_severity absent", {
  curr <- make_curr()[, rev(names(make_curr()))]
  cfg  <- base_config()
  cfg$format <- "fwf"
  res <- compare_column_order(curr, make_prev(), cfg)
  expect_equal(res[[1]]$status, "FAIL")
})

# -- flag_* config keys --------------------------------------------------------

test_that("compare_schema() suppresses new columns when flag_new_columns=FALSE", {
  curr <- make_curr()
  curr$extra_col <- "x"
  cfg <- base_config()
  cfg$rules$flag_new_columns <- FALSE
  res <- compare_schema(curr, make_prev(), cfg)
  r02a <- Filter(\(r) r$check_id == "CP-02a", res)
  expect_equal(r02a[[1]]$status, "PASS")
  expect_false(grepl("New columns", r02a[[1]]$observed))
  expect_equal(attr(res, "new_cols"), "extra_col")  # still tracked in snapshot database
})

test_that("compare_schema() suppresses dropped columns when flag_dropped_columns=FALSE", {
  prev <- make_prev()
  prev$ghost_col <- "x"
  cfg <- base_config()
  cfg$rules$flag_dropped_columns <- FALSE
  res <- compare_schema(make_curr(), prev, cfg)
  r02b <- Filter(\(r) r$check_id == "CP-02b", res)
  expect_equal(r02b[[1]]$status, "PASS")
  expect_false(grepl("Dropped", r02b[[1]]$observed))
  expect_equal(attr(res, "dropped_cols"), "ghost_col")
})

test_that("compare_schema() suppresses type changes when flag_type_changes=FALSE", {
  prev <- make_prev()
  prev$account_balance <- c("high", "low", "mid", "zero", "neg")
  cfg <- base_config()
  cfg$rules$flag_type_changes <- FALSE
  res <- compare_schema(make_curr(), prev, cfg)
  r02c <- Filter(\(r) r$check_id == "CP-02c", res)
  expect_equal(r02c[[1]]$status, "PASS")
  expect_false(grepl("Type changes", r02c[[1]]$observed))
})

test_that("compare_column_order() returns empty list when flag_column_order_change=FALSE", {
  curr <- make_curr()[, rev(names(make_curr()))]
  cfg  <- base_config()
  cfg$rules$flag_column_order_change <- FALSE
  res  <- compare_column_order(curr, make_prev(), cfg)
  expect_length(res, 0)
})

test_that("run_comparison_checks() preserves new_cols and dropped_cols attributes", {
  curr <- make_curr()
  curr$extra_col <- "x"
  prev <- make_prev()
  prev$ghost_col <- "y"
  res <- run_comparison_checks(curr, prev, base_config())
  expect_equal(attr(res, "new_cols"),     "extra_col")
  expect_equal(attr(res, "dropped_cols"), "ghost_col")
})

test_that("run_comparison_checks() attributes are NULL when no schema changes", {
  res <- run_comparison_checks(make_curr(), make_prev(), base_config())
  expect_length(attr(res, "new_cols"),     0)
  expect_length(attr(res, "dropped_cols"), 0)
})

# -- DuckDB parity tests -------------------------------------------------------

duck_compare_setup <- function() {
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "curr", make_curr())
  DBI::dbWriteTable(con, "prev", make_prev())
  list(con = con, curr = "curr", prev = "prev")
}

test_that("compare_row_count() DuckDB path matches R path", {
  s <- duck_compare_setup()
  on.exit(DBI::dbDisconnect(s$con))
  r_res  <- compare_row_count(make_curr(), make_prev(), base_config())
  db_res <- compare_row_count(s$curr, s$prev, base_config(), con = s$con)
  expect_equal(r_res[[1]]$status, db_res[[1]]$status)
})

test_that("compare_missing_rate() DuckDB path matches R path", {
  s <- duck_compare_setup()
  on.exit(DBI::dbDisconnect(s$con))
  r_res  <- compare_missing_rate(make_curr(), make_prev(), base_config())
  db_res <- compare_missing_rate(s$curr, s$prev, base_config(), con = s$con)
  r_stat <- vapply(r_res,  \(r) r$status, character(1))
  d_stat <- vapply(db_res, \(r) r$status, character(1))
  expect_equal(r_stat, d_stat)
})

test_that("compare_schema() DuckDB path detects new column", {
  curr <- make_curr()
  curr$extra <- "x"
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con))
  DBI::dbWriteTable(con, "c", curr)
  DBI::dbWriteTable(con, "p", make_prev())
  r_res  <- compare_schema(curr, make_prev(), base_config())
  db_res <- compare_schema("c", "p", base_config(), con = con)
  r02a_r  <- Filter(\(r) r$check_id == "CP-02a", r_res)
  r02a_db <- Filter(\(r) r$check_id == "CP-02a", db_res)
  expect_equal(r02a_r[[1]]$status,  r02a_db[[1]]$status)
  expect_equal(attr(r_res, "new_cols"), attr(db_res, "new_cols"))
})

test_that("compare_non_numeric_rate() DuckDB path matches R path", {
  s <- duck_compare_setup()
  on.exit(DBI::dbDisconnect(s$con))
  r_res  <- compare_non_numeric_rate(make_curr(), make_prev(), base_config())
  db_res <- compare_non_numeric_rate(s$curr, s$prev, base_config(), con = s$con)
  r_stat <- vapply(r_res,  \(r) r$status, character(1))
  d_stat <- vapply(db_res, \(r) r$status, character(1))
  expect_equal(r_stat, d_stat)
})
