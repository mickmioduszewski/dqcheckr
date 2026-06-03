

# -- QC-01 Missing rate --------------------------------------------------------

test_that("check_missing_rate() returns PASS when missing rate is within threshold", {
  res      <- check_missing_rate(make_accounts_df(), base_config())
  statuses <- vapply(res, `[[`, character(1), "status")
  expect_true(all(statuses == "PASS"))
})

test_that("check_missing_rate() returns FAIL when column exceeds threshold", {
  df       <- make_accounts_df()
  df$name[2:5] <- NA
  res      <- check_missing_rate(df, base_config())
  name_res <- Filter(\(r) r$column == "name", res)
  expect_equal(name_res[[1]]$status, "FAIL")
})

# -- QC-02 Empty column --------------------------------------------------------

test_that("check_empty_column() returns PASS when no column is entirely empty", {
  res <- check_empty_column(make_accounts_df(), base_config())
  expect_true(all(vapply(res, \(r) r$status == "PASS", logical(1))))
})

test_that("check_empty_column() returns FAIL for entirely empty column", {
  df                   <- make_accounts_df()
  df$account_balance   <- NA_character_
  res                  <- check_empty_column(df, base_config())
  bal                  <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "FAIL")
})

# -- QC-03 Duplicate rows ------------------------------------------------------

test_that("check_duplicate_rows() returns PASS when no duplicate rows", {
  res <- check_duplicate_rows(make_accounts_df(), base_config())
  expect_equal(res[[1]]$status, "PASS")
})

test_that("check_duplicate_rows() returns WARN when duplicate rows exist", {
  df  <- rbind(make_accounts_df(), make_accounts_df()[2, ])
  res <- check_duplicate_rows(df, base_config())
  expect_equal(res[[1]]$status, "WARN")
})

# -- QC-04 Row count -----------------------------------------------------------

test_that("check_row_count() returns INFO with correct count", {
  res <- check_row_count(make_accounts_df(), base_config())
  expect_equal(res[[1]]$status, "INFO")
  expect_equal(res[[1]]$observed, "5")
})

# -- QC-05 Column count --------------------------------------------------------

test_that("check_col_count() returns INFO with correct count", {
  df  <- make_accounts_df()
  res <- check_col_count(df, base_config())
  expect_equal(res[[1]]$status, "INFO")
  expect_equal(res[[1]]$observed, as.character(ncol(df)))
})

# -- QC-06 Inferred types ------------------------------------------------------

test_that("check_inferred_types() returns INFO for each column", {
  df  <- make_accounts_df()
  res <- check_inferred_types(df, base_config())
  expect_equal(length(res), ncol(df))
  expect_true(all(vapply(res, \(r) r$status == "INFO", logical(1))))
})

test_that("check_inferred_types() infers 'numeric' for account_balance", {
  res <- check_inferred_types(make_accounts_df(), base_config())
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$observed, "numeric")
})

test_that("check_inferred_types() infers 'date' for created_date", {
  res  <- check_inferred_types(make_accounts_df(), base_config())
  date <- Filter(\(r) r$column == "created_date", res)
  expect_equal(date[[1]]$observed, "date")
})

# -- QC-07 Numeric stats -------------------------------------------------------

test_that("check_numeric_stats() returns INFO for numeric columns", {
  res <- check_numeric_stats(make_accounts_df(), base_config())
  expect_true(length(res) > 0)
  expect_true(all(vapply(res, \(r) r$status == "INFO", logical(1))))
})

test_that("check_numeric_stats() observed contains min/max/mean/sd", {
  res <- check_numeric_stats(make_accounts_df(), base_config())
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_match(bal[[1]]$observed, "min=")
  expect_match(bal[[1]]$observed, "max=")
  expect_match(bal[[1]]$observed, "mean=")
})

# -- QC-08 Distinct counts -----------------------------------------------------

test_that("check_distinct_counts() returns INFO for character columns", {
  res <- check_distinct_counts(make_accounts_df(), base_config())
  expect_true(length(res) > 0)
  expect_true(all(vapply(res, \(r) r$status == "INFO", logical(1))))
})

# -- QC-09 Allowed values ------------------------------------------------------

test_that("check_allowed_values() returns PASS when all values are allowed", {
  cfg <- base_config(list(column_rules = list(
    country_code = list(allowed_values = c("GB", "US", "DE", "FR"))
  )))
  res <- check_allowed_values(make_accounts_df(), cfg)
  cc  <- Filter(\(r) r$column == "country_code", res)
  expect_equal(cc[[1]]$status, "PASS")
})

test_that("check_allowed_values() returns FAIL when disallowed values present", {
  df               <- make_accounts_df()
  df$country_code[1] <- "ZZ"
  cfg <- base_config(list(column_rules = list(
    country_code = list(allowed_values = c("GB", "US", "DE", "FR"))
  )))
  res <- check_allowed_values(df, cfg)
  cc  <- Filter(\(r) r$column == "country_code", res)
  expect_equal(cc[[1]]$status, "FAIL")
  expect_match(cc[[1]]$observed, "ZZ")
})

test_that("check_allowed_values() returns empty list when no column_rules", {
  res <- check_allowed_values(make_accounts_df(), base_config())
  expect_equal(length(res), 0)
})

# -- QC-10 Numeric bounds ------------------------------------------------------

test_that("check_numeric_bounds() returns PASS when all values within range", {
  cfg <- base_config(list(column_rules = list(
    account_balance = list(min_value = 0, max_value = 1000000)
  )))
  res <- check_numeric_bounds(make_accounts_df(), cfg)
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "PASS")
})

test_that("check_numeric_bounds() returns FAIL when value below min", {
  df                    <- make_accounts_df()
  df$account_balance[1] <- "-500"
  cfg <- base_config(list(column_rules = list(
    account_balance = list(min_value = 0, max_value = 1000000)
  )))
  res <- check_numeric_bounds(df, cfg)
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "FAIL")
})

test_that("check_numeric_bounds() returns FAIL when value above max", {
  df                    <- make_accounts_df()
  df$account_balance[1] <- "2000000"
  cfg <- base_config(list(column_rules = list(
    account_balance = list(min_value = 0, max_value = 1000000)
  )))
  res <- check_numeric_bounds(df, cfg)
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "FAIL")
})

# -- QC-11 Non-numeric values --------------------------------------------------

test_that("check_non_numeric() returns PASS when all numeric column values are numeric", {
  res <- check_non_numeric(make_accounts_df(), base_config())
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "PASS")
})

test_that("check_non_numeric() returns FAIL when non-numeric rate exceeds threshold", {
  # 10 rows: 1 bad = 10% non-numeric. infer_col_type still returns 'numeric'
  # (90% numeric >= 90% threshold). 10% > 1% max_non_numeric_rate -> FAIL.
  df <- make_accounts_df()[rep(seq_len(nrow(make_accounts_df())), 2), ]
  df$account_balance[1] <- "N/A"
  res <- check_non_numeric(df, base_config())
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "FAIL")
})

test_that("check_non_numeric() returns WARN when non-numeric present but below threshold", {
  df100               <- make_accounts_df()[rep(1:5, 20), ]
  df100$account_balance[1] <- "N/A"
  cfg <- base_config(list(rules = list(
    max_missing_rate = 0.05, max_non_numeric_rate = 0.05,
    min_row_count = 0, max_row_count_change_pct = 0.10,
    max_numeric_mean_shift_pct = 0.20,
    max_missing_rate_change_pp = 2.0,
    max_non_numeric_rate_change_pp = 1.0
  )))
  res <- check_non_numeric(df100, cfg)
  bal <- Filter(\(r) r$column == "account_balance", res)
  expect_equal(bal[[1]]$status, "WARN")
})

# -- QC-12 Key uniqueness ------------------------------------------------------

test_that("check_key_uniqueness() returns PASS for unique key column", {
  cfg <- base_config(list(key_columns = "id"))
  res <- check_key_uniqueness(make_accounts_df(), cfg)
  expect_equal(res[[1]]$status, "PASS")
})

test_that("check_key_uniqueness() returns FAIL when duplicate key exists", {
  df       <- make_accounts_df()
  df$id[2] <- "ID001"
  cfg <- base_config(list(key_columns = "id"))
  res <- check_key_uniqueness(df, cfg)
  expect_equal(res[[1]]$status, "FAIL")
})

test_that("check_key_uniqueness() returns empty list when no key_columns configured", {
  res <- check_key_uniqueness(make_accounts_df(), base_config())
  expect_equal(length(res), 0)
})

# -- QC-13 Pattern -------------------------------------------------------------

test_that("check_pattern() returns PASS when all values match pattern", {
  cfg <- base_config(list(column_rules = list(
    country_code = list(pattern = "^[A-Z]{2}$")
  )))
  res <- check_pattern(make_accounts_df(), cfg)
  cc  <- Filter(\(r) r$column == "country_code", res)
  expect_equal(cc[[1]]$status, "PASS")
})

test_that("check_pattern() returns FAIL when values violate pattern", {
  df                   <- make_accounts_df()
  df$country_code[1]   <- "gb"
  cfg <- base_config(list(column_rules = list(
    country_code = list(pattern = "^[A-Z]{2}$")
  )))
  res <- check_pattern(df, cfg)
  cc  <- Filter(\(r) r$column == "country_code", res)
  expect_equal(cc[[1]]$status, "FAIL")
})

# -- QC-14 Minimum row count ---------------------------------------------------

test_that("check_min_row_count() returns PASS when disabled (min_row_count=0)", {
  res <- check_min_row_count(make_accounts_df(), base_config())
  expect_equal(res[[1]]$status, "PASS")
})

test_that("check_min_row_count() returns FAIL when row count below threshold", {
  cfg <- base_config(list(rules = list(
    max_missing_rate = 0.05, max_non_numeric_rate = 0.01,
    min_row_count = 1000,
    max_row_count_change_pct = 0.10, max_numeric_mean_shift_pct = 0.20,
    max_missing_rate_change_pp = 2.0, max_non_numeric_rate_change_pp = 1.0
  )))
  res <- check_min_row_count(make_accounts_df(), cfg)
  expect_equal(res[[1]]$status, "FAIL")
})

# -- SC-01 / SC-02 Schema contract ---------------------------------------------

test_that("check_schema_contract() returns PASS when columns match exactly", {
  cfg <- base_config(list(
    expected_columns = c("id", "name", "country_code",
                         "account_status", "account_balance", "created_date")
  ))
  res <- check_schema_contract(make_accounts_df(), cfg)
  expect_true(all(vapply(res, \(r) r$status == "PASS", logical(1))))
})

test_that("check_schema_contract() returns FAIL for extra column (SC-01)", {
  df           <- make_accounts_df()
  df$extra_col <- "x"
  cfg <- base_config(list(
    expected_columns = c("id", "name", "country_code",
                         "account_status", "account_balance", "created_date")
  ))
  res  <- check_schema_contract(df, cfg)
  sc01 <- Filter(\(r) r$check_id == "SC-01", res)
  expect_true(any(vapply(sc01, \(r) r$status == "FAIL", logical(1))))
})

test_that("check_schema_contract() returns FAIL for missing column (SC-02)", {
  df  <- make_accounts_df()[, -3]
  cfg <- base_config(list(
    expected_columns = c("id", "name", "country_code",
                         "account_status", "account_balance", "created_date")
  ))
  res  <- check_schema_contract(df, cfg)
  sc02 <- Filter(\(r) r$check_id == "SC-02", res)
  expect_true(any(vapply(sc02, \(r) r$status == "FAIL", logical(1))))
})

test_that("check_schema_contract() returns empty list when expected_columns not set", {
  res <- check_schema_contract(make_accounts_df(), base_config())
  expect_equal(length(res), 0)
})

# -- QC-09 observed capping (RC-04) --------------------------------------------

test_that("check_allowed_values() caps observed at 20 values with suffix", {
  df  <- data.frame(x = paste0("v", 1:30), stringsAsFactors = FALSE)
  cfg <- base_config(list(column_rules = list(x = list(allowed_values = c("v1")))))
  res <- check_allowed_values(df, cfg)
  expect_match(res[[1]]$observed, "and \\d+ more")
})

# -- QC-11 warn_non_numeric_rate (C-01) ----------------------------------------

test_that("check_non_numeric() emits WARN when rate is between warn and fail thresholds", {
  # 10/11 = 90.9% parseable → inferred as numeric; 1/11 non-numeric → WARN
  df   <- data.frame(x = c("1","2","3","4","5","6","7","8","9","10","bad"),
                     stringsAsFactors = FALSE)
  cfg  <- base_config(list(rules = list(
    max_missing_rate = 0.05, max_non_numeric_rate = 0.30,
    warn_non_numeric_rate = 0.0, type_inference_threshold = 0.90
  )))
  res  <- check_non_numeric(df, cfg)
  xres <- Filter(\(r) r$column == "x", res)
  expect_equal(xres[[1]]$status, "WARN")
})

test_that("check_non_numeric() emits PASS when rate equals zero with warn threshold 0.0", {
  df  <- data.frame(x = c("1", "2", "3"), stringsAsFactors = FALSE)
  cfg <- base_config(list(rules = list(
    max_missing_rate = 0.05, max_non_numeric_rate = 0.01,
    warn_non_numeric_rate = 0.0, type_inference_threshold = 0.90
  )))
  res  <- check_non_numeric(df, cfg)
  xres <- Filter(\(r) r$column == "x", res)
  expect_equal(xres[[1]]$status, "PASS")
})

# -- QC-12 composite key (M-03/B-03) ------------------------------------------

test_that("check_key_uniqueness() detects composite key duplicates", {
  df  <- data.frame(
    a = c("X", "X", "X"),
    b = c("1", "2", "1"),   # (X,1) appears twice
    stringsAsFactors = FALSE
  )
  cfg <- base_config(list(key_columns = c("a", "b")))
  res <- check_key_uniqueness(df, cfg)
  expect_equal(res[[1]]$status, "FAIL")
  expect_match(res[[1]]$check_id, "QC-12")
})

test_that("check_key_uniqueness() PASS for unique composite key", {
  df  <- data.frame(a = c("X","X","Y"), b = c("1","2","1"), stringsAsFactors = FALSE)
  cfg <- base_config(list(key_columns = c("a", "b")))
  res <- check_key_uniqueness(df, cfg)
  expect_equal(res[[1]]$status, "PASS")
})

test_that("check_key_uniqueness() reports missing composite key column", {
  df  <- data.frame(a = c("X"), stringsAsFactors = FALSE)
  cfg <- base_config(list(key_columns = c("a", "missing_col")))
  res <- check_key_uniqueness(df, cfg)
  expect_equal(res[[1]]$status, "FAIL")
  expect_match(res[[1]]$observed, "missing_col")
})

# -- QC-14 max_row_count (M-08) ------------------------------------------------

test_that("check_min_row_count() emits FAIL when rows exceed max_row_count", {
  df  <- data.frame(x = 1:10, stringsAsFactors = FALSE)
  cfg <- base_config(list(rules = list(min_row_count = 0, max_row_count = 5)))
  res <- check_min_row_count(df, cfg)
  max_r <- Filter(\(r) r$check_name == "Maximum row count", res)
  expect_equal(max_r[[1]]$status, "FAIL")
})

test_that("check_min_row_count() PASS when rows within max_row_count", {
  df  <- data.frame(x = 1:5, stringsAsFactors = FALSE)
  cfg <- base_config(list(rules = list(min_row_count = 0, max_row_count = 10)))
  res <- check_min_row_count(df, cfg)
  max_r <- Filter(\(r) r$check_name == "Maximum row count", res)
  expect_equal(max_r[[1]]$status, "PASS")
})

# -- QC-15 outlier detection (M-06) --------------------------------------------

test_that("check_outliers() returns PASS when no threshold configured", {
  df  <- make_accounts_df()
  cfg <- base_config()
  res <- check_outliers(df, cfg)
  statuses <- vapply(res, `[[`, character(1), "status")
  expect_true(all(statuses == "PASS"))
})

test_that("check_outliers() detects Z-score outliers", {
  outlier_val <- 10000
  df  <- data.frame(
    x = as.character(c(1, 2, 3, 2, 1, outlier_val)),
    stringsAsFactors = FALSE
  )
  cfg <- base_config(list(rules = list(
    max_missing_rate = 0.05, max_non_numeric_rate = 0.01,
    type_inference_threshold = 0.90, max_z_score = 2.0
  )))
  res  <- check_outliers(df, cfg)
  xres <- Filter(\(r) r$column == "x", res)
  expect_equal(xres[[1]]$status, "FAIL")
})

test_that("check_outliers() detects IQR outliers", {
  df  <- data.frame(
    x = as.character(c(1, 2, 3, 2, 1, 999)),
    stringsAsFactors = FALSE
  )
  cfg <- base_config(list(rules = list(
    max_missing_rate = 0.05, max_non_numeric_rate = 0.01,
    type_inference_threshold = 0.90, iqr_fence_multiplier = 1.5
  )))
  res  <- check_outliers(df, cfg)
  xres <- Filter(\(r) r$column == "x", res)
  expect_equal(xres[[1]]$status, "FAIL")
})

test_that("check_outliers() skips non-numeric columns", {
  df  <- data.frame(cat = c("a", "b", "c", "d", "e"), stringsAsFactors = FALSE)
  cfg <- base_config(list(rules = list(
    max_missing_rate = 0.05, max_non_numeric_rate = 0.01,
    type_inference_threshold = 0.90, max_z_score = 2.0
  )))
  res <- check_outliers(df, cfg)
  expect_length(res, 0)  # no results for character column
})
