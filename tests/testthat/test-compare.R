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

# ── CP-01 Row count change ────────────────────────────────────────────────────

test_that("compare_row_count() returns PASS when change is within threshold", {
  res <- compare_row_count(make_curr(), make_prev(), base_config())
  expect_equal(res[[1]]$status, "PASS")
})

test_that("compare_row_count() returns WARN when change exceeds threshold", {
  curr <- make_curr()[1:2, ]
  res  <- compare_row_count(curr, make_prev(), base_config())
  expect_equal(res[[1]]$status, "WARN")
})

# ── CP-02 Schema diff ─────────────────────────────────────────────────────────

test_that("compare_schema() returns PASS when schemas are identical", {
  res <- compare_schema(make_curr(), make_prev(), base_config())
  expect_equal(res[[1]]$status, "PASS")
})

test_that("compare_schema() returns WARN when current has new column", {
  curr       <- make_curr()
  curr$extra <- "x"
  res <- compare_schema(curr, make_prev(), base_config())
  expect_equal(res[[1]]$status, "WARN")
  expect_true("extra" %in% attr(res, "new_cols"))
})

test_that("compare_schema() returns WARN when column is dropped", {
  curr <- make_curr()[, -3]
  res  <- compare_schema(curr, make_prev(), base_config())
  expect_equal(res[[1]]$status, "WARN")
  expect_true("country_code" %in% attr(res, "dropped_cols"))
})

test_that("compare_schema() returns WARN on type change", {
  curr                  <- make_curr()
  curr$account_balance  <- c("high", "low", "medium", "high", "low")
  res <- compare_schema(curr, make_prev(), base_config())
  expect_equal(res[[1]]$status, "WARN")
})

test_that("compare_schema() attaches new_cols and dropped_cols attributes", {
  curr       <- make_curr()
  curr$new1  <- "x"
  res <- compare_schema(curr, make_prev(), base_config())
  expect_false(is.null(attr(res, "new_cols")))
  expect_false(is.null(attr(res, "dropped_cols")))
})

# ── CP-03 Missing rate change ─────────────────────────────────────────────────

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

# ── CP-04 Numeric mean shift ──────────────────────────────────────────────────

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

# ── CP-05 New distinct values ─────────────────────────────────────────────────

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

# ── CP-06 Dropped distinct values ────────────────────────────────────────────

test_that("compare_dropped_values() returns INFO always", {
  res <- compare_dropped_values(make_curr(), make_prev(), base_config())
  expect_true(all(vapply(res, \(r) r$status == "INFO", logical(1))))
})

# ── CP-07 Non-numeric rate change ─────────────────────────────────────────────

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

# ── CP-08 Column order ────────────────────────────────────────────────────────

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
