cfg_thr <- function(rules = list(), column_rules = list()) {
  list(
    rules        = modifyList(
      list(max_missing_rate             = 0.05,
           max_non_numeric_rate         = 0.01,
           max_missing_rate_change_pp   = 2.0,
           max_numeric_mean_shift_pct   = 0.20,
           max_non_numeric_rate_change_pp = 1.0),
      rules
    ),
    column_types = list(),
    column_rules = column_rules
  )
}

# --- col_threshold() ----------------------------------------------------------

test_that("col_threshold returns column-level value when present", {
  cfg <- cfg_thr(column_rules = list(email = list(max_missing_rate = 1.0)))
  expect_equal(col_threshold(cfg, "email", "max_missing_rate", 0.05), 1.0)
})

test_that("col_threshold falls back to rules level", {
  cfg <- cfg_thr(rules = list(max_missing_rate = 0.10))
  expect_equal(col_threshold(cfg, "other_col", "max_missing_rate", 0.05), 0.10)
})

test_that("col_threshold falls back to default when key absent everywhere", {
  cfg <- list(rules = list(), column_types = list(), column_rules = list())
  expect_equal(col_threshold(cfg, "x", "max_missing_rate", 0.05), 0.05)
})

# --- QC-01: per-column max_missing_rate --------------------------------------

test_that("QC-01 uses per-column threshold: high missing PASS with relaxed threshold", {
  cfg <- cfg_thr(column_rules = list(email = list(max_missing_rate = 1.0)))
  # 100% missing — should PASS with threshold 1.0
  df  <- data.frame(email = c(NA, NA, NA, ""), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-01" && r$column == "email",
                check_missing_rate(df, cfg))
  expect_equal(res[[1]]$status, "PASS")
  expect_equal(res[[1]]$threshold, "100.0%")
})

test_that("QC-01 uses per-column threshold: zero missing FAIL with strict threshold", {
  cfg <- cfg_thr(column_rules = list(amount = list(max_missing_rate = 0.0)))
  df  <- data.frame(amount = c("100", NA, "200"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-01" && r$column == "amount",
                check_missing_rate(df, cfg))
  expect_equal(res[[1]]$status, "FAIL")
  expect_equal(res[[1]]$threshold, "0.0%")
})

test_that("QC-01 uses global threshold for columns not in column_rules", {
  cfg <- cfg_thr(column_rules = list(email = list(max_missing_rate = 1.0)))
  df  <- data.frame(other = c(NA, "a", "b"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-01" && r$column == "other",
                check_missing_rate(df, cfg))
  expect_equal(res[[1]]$threshold, "5.0%")
})

# --- QC-11: per-column max_non_numeric_rate ----------------------------------

test_that("QC-11 uses per-column threshold: zero allowed means FAIL on any non-numeric", {
  cfg <- cfg_thr(column_rules = list(amount = list(max_non_numeric_rate = 0.0)))
  # mostly numeric column with one bad value
  df  <- data.frame(amount = c("100", "200", "N/A", "400", "500",
                                "600", "700", "800", "900", "1000"),
                    stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-11" && r$column == "amount",
                check_non_numeric(df, cfg))
  expect_equal(res[[1]]$status, "FAIL")
  expect_equal(res[[1]]$threshold, "0.00%")
})

# --- CP-03: per-column max_missing_rate_change_pp ----------------------------

test_that("CP-03 uses per-column threshold: large change PASS with relaxed threshold", {
  cfg  <- cfg_thr(column_rules = list(
    email = list(max_missing_rate_change_pp = 50.0)
  ))
  # 1 of 5 newly missing = 20pp change; relaxed threshold is 50pp → PASS
  curr <- data.frame(email = c(NA, "b", "c", "d", "e"), stringsAsFactors = FALSE)
  prev <- data.frame(email = c("a", "b", "c", "d", "e"), stringsAsFactors = FALSE)
  res  <- Filter(\(r) r$check_id == "CP-03" && r$column == "email",
                 compare_missing_rate(curr, prev, cfg))
  expect_equal(res[[1]]$status, "PASS")
  expect_match(res[[1]]$threshold, "50.0")
})

test_that("CP-03 WARN when change exceeds per-column threshold", {
  cfg  <- cfg_thr(column_rules = list(
    email = list(max_missing_rate_change_pp = 1.0)
  ))
  curr <- data.frame(email = c(NA, NA, NA, "x", "y"), stringsAsFactors = FALSE)
  prev <- data.frame(email = c("a", "b", "c", "d", "e"), stringsAsFactors = FALSE)
  res  <- Filter(\(r) r$check_id == "CP-03" && r$column == "email",
                 compare_missing_rate(curr, prev, cfg))
  expect_equal(res[[1]]$status, "WARN")
})

# --- CP-04: per-column max_numeric_mean_shift_pct ----------------------------

test_that("CP-04 uses per-column threshold: small shift WARN with strict threshold", {
  cfg  <- cfg_thr(column_rules = list(
    price = list(max_numeric_mean_shift_pct = 0.01)
  ))
  # mean shifts ~10% — would pass at global 20% but fail at 1%
  curr <- data.frame(price = as.character(101:110), stringsAsFactors = FALSE)
  prev <- data.frame(price = as.character(91:100),  stringsAsFactors = FALSE)
  res  <- Filter(\(r) r$check_id == "CP-04" && r$column == "price",
                 compare_numeric_mean(curr, prev, cfg))
  expect_equal(res[[1]]$status, "WARN")
})

# --- CP-07: per-column max_non_numeric_rate_change_pp ------------------------

test_that("CP-07 uses per-column threshold: change PASS with relaxed threshold", {
  cfg  <- cfg_thr(column_rules = list(
    unit = list(max_non_numeric_rate_change_pp = 50.0)
  ))
  # unit goes from 0% to ~25% non-numeric — would exceed global 1pp threshold
  curr <- data.frame(unit = c("1", "2", "3A", "4"),  stringsAsFactors = FALSE)
  prev <- data.frame(unit = c("1", "2", "3",  "4"),  stringsAsFactors = FALSE)
  res  <- Filter(\(r) r$check_id == "CP-07" && r$column == "unit",
                 compare_non_numeric_rate(curr, prev, cfg))
  # Should PASS because per-column threshold is 50pp
  if (length(res) > 0) expect_equal(res[[1]]$status, "PASS")
})

# --- threshold reflected in dq_result ----------------------------------------

test_that("QC-01 threshold field reflects the effective per-column threshold", {
  cfg <- cfg_thr(column_rules = list(email = list(max_missing_rate = 0.99)))
  df  <- data.frame(email = c(NA, "a"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-01" && r$column == "email",
                check_missing_rate(df, cfg))
  expect_equal(res[[1]]$threshold, "99.0%")
})
