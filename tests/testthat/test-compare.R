

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

test_that("compare_schema() returns WARN when column is dropped (CP-02b)", {
  curr <- make_curr()[, -3]
  res  <- compare_schema(curr, make_prev(), base_config())
  # res[[1]] = CP-02a (new cols, PASS); res[[2]] = CP-02b (dropped cols, WARN)
  expect_equal(res[[2]]$status, "WARN")
  expect_equal(res[[2]]$check_id, "CP-02b")
  expect_true("country_code" %in% attr(res, "dropped_cols"))
})

test_that("compare_schema() returns WARN on type change (CP-02c)", {
  curr                  <- make_curr()
  curr$account_balance  <- c("high", "low", "medium", "high", "low")
  res <- compare_schema(curr, make_prev(), base_config())
  # res[[3]] = CP-02c (type changes)
  expect_equal(res[[3]]$status, "WARN")
  expect_equal(res[[3]]$check_id, "CP-02c")
})

test_that("compare_schema() returns 3 results with correct check_ids", {
  res <- compare_schema(make_curr(), make_prev(), base_config())
  expect_length(res, 3L)
  expect_equal(vapply(res, `[[`, character(1), "check_id"),
               c("CP-02a", "CP-02b", "CP-02c"))
})

test_that("compare_schema() attaches new_cols, dropped_cols and type_changed_cols attributes", {
  curr       <- make_curr()
  curr$new1  <- "x"
  res <- compare_schema(curr, make_prev(), base_config())
  expect_false(is.null(attr(res, "new_cols")))
  expect_false(is.null(attr(res, "dropped_cols")))
  expect_false(is.null(attr(res, "type_changed_cols")))
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

# -- CP-07 Non-numeric rate change ---------------------------------------------

test_that("compare_non_numeric_rate() returns PASS when rate unchanged", {
  res <- compare_non_numeric_rate(make_curr(), make_prev(), base_config())
  statuses <- vapply(res, `[[`, character(1), "status")
  expect_true(all(statuses %in% c("PASS", "INFO")))
})

test_that("compare_non_numeric_rate() returns WARN when rate increases significantly", {
  # Need t_curr = "numeric": replicate to 10 rows so 9/10 parseable meets 90% threshold
  curr <- make_curr()[rep(1:5, 2), ]
  curr$account_balance[1] <- "bad"
  res <- compare_non_numeric_rate(curr, make_prev(), base_config())
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "WARN")
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

# -- flag_* config keys --------------------------------------------------------

test_that("compare_schema() suppresses new columns when flag_new_columns=FALSE", {
  curr <- make_curr()
  curr$extra_col <- "x"
  cfg <- base_config()
  cfg$rules$flag_new_columns <- FALSE
  res <- compare_schema(curr, make_prev(), cfg)
  # CP-02a should be PASS; observed is "None." (not "New: ...")
  expect_equal(res[[1]]$status, "PASS")
  expect_false(grepl("^New:", res[[1]]$observed))
  expect_equal(attr(res, "new_cols"), "extra_col")  # still tracked for SQLite
})

test_that("compare_schema() suppresses dropped columns when flag_dropped_columns=FALSE", {
  prev <- make_prev()
  prev$ghost_col <- "x"
  cfg <- base_config()
  cfg$rules$flag_dropped_columns <- FALSE
  res <- compare_schema(make_curr(), prev, cfg)
  # CP-02b should be PASS
  expect_equal(res[[2]]$status, "PASS")
  expect_false(grepl("^Dropped:", res[[2]]$observed))
  expect_equal(attr(res, "dropped_cols"), "ghost_col")
})

test_that("compare_schema() suppresses type changes when flag_type_changes=FALSE", {
  prev <- make_prev()
  prev$account_balance <- c("high", "low", "mid", "zero", "neg")
  cfg <- base_config()
  cfg$rules$flag_type_changes <- FALSE
  res <- compare_schema(make_curr(), prev, cfg)
  # CP-02c should be PASS
  expect_equal(res[[3]]$status, "PASS")
  expect_false(grepl("^Type changes:", res[[3]]$observed))
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

# -- CP-03 configurable severity (B-07) ----------------------------------------

test_that("compare_missing_rate() emits FAIL when missing_rate_change_severity=fail", {
  curr      <- make_curr()
  curr$name <- NA_character_
  cfg       <- base_config()
  cfg$rules$missing_rate_change_severity <- "fail"
  res    <- compare_missing_rate(curr, make_prev(), cfg)
  name_r <- Filter(\(r) r$column == "name", res)
  expect_equal(name_r[[1]]$status, "FAIL")
})

# -- CP-07 always emits PASS (G-02) --------------------------------------------

test_that("compare_non_numeric_rate() emits a result for all eligible columns including no-change (G-02)", {
  res <- compare_non_numeric_rate(make_curr(), make_prev(), base_config())
  # account_balance is numeric in both snapshots; must have a result
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_true(length(bal) >= 1)
  expect_equal(bal[[1]]$status, "PASS")
})

# -- CP-08 configurable severity (C-02) ----------------------------------------

test_that("compare_column_order() respects column_order_severity=fail for CSV", {
  curr <- make_curr()[, rev(names(make_curr()))]
  cfg  <- base_config()
  cfg$format <- "csv"
  cfg$rules$column_order_severity <- "fail"
  res <- compare_column_order(curr, make_prev(), cfg)
  expect_equal(res[[1]]$status, "FAIL")
})

# -- run_comparison_checks() carries type_changed_cols attribute ---------------

test_that("run_comparison_checks() carries type_changed_cols attribute", {
  curr                 <- make_curr()
  curr$account_balance <- c("high", "low", "med", "low", "high")
  res <- run_comparison_checks(curr, make_prev(), base_config())
  tc  <- attr(res, "type_changed_cols")
  expect_true(any(grepl("account_balance", tc)))
})

# -- Zero-row current delivery (0.2.3, B-01) ------------------------------------

test_that("run_comparison_checks() handles a zero-row current delivery without error", {
  prev <- make_accounts_df()
  curr <- prev[0, ]
  res  <- run_comparison_checks(curr, prev, base_config())
  expect_true(length(res) > 0)
  statuses <- vapply(res, `[[`, character(1), "status")
  expect_true(all(statuses %in% c("PASS", "WARN", "FAIL", "INFO")))
})

# -- CP-04 unparseable current column (0.2.3, B-02) -------------------------------

test_that("CP-04 emits WARN instead of erroring when the current column has no parseable numerics", {
  prev <- make_accounts_df()
  curr <- make_accounts_df()
  curr$account_balance <- letters[1:5]                       # nothing parses
  cfg  <- base_config(list(column_types = list(account_balance = "numeric")))
  res  <- run_comparison_checks(curr, prev, cfg)
  cp04 <- Filter(\(r) r$check_id == "CP-04" &&
                      !is.na(r$column) && r$column == "account_balance", res)
  expect_length(cp04, 1)
  expect_equal(cp04[[1]]$status, "WARN")
  expect_match(cp04[[1]]$message, "cannot be computed")
})

# -- Precomputed types argument (0.2.3, P-01) -----------------------------------

test_that("run_comparison_checks() with precomputed types matches default behaviour", {
  curr <- make_accounts_df()
  prev <- make_accounts_df()
  prev$account_balance <- c("100", "200", "300", "400", "500")
  cfg  <- base_config()
  types_curr <- vapply(names(curr), \(c) resolve_col_type(c, curr[[c]], cfg), character(1))
  types_prev <- vapply(names(prev), \(c) resolve_col_type(c, prev[[c]], cfg), character(1))
  expect_identical(
    run_comparison_checks(curr, prev, cfg,
                          types_current = types_curr, types_previous = types_prev),
    run_comparison_checks(curr, prev, cfg)
  )
})
