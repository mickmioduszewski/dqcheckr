
# -- dq_result() ---------------------------------------------------------------

test_that("dq_result() returns a named list with all seven fields", {
  r <- dq_result("QC-01", "Missing rate", column = "name",
                 status = "PASS", observed = "0%", message = "All good")
  expect_type(r, "list")
  expect_named(r, c("check_id", "check_name", "column", "status",
                    "observed", "threshold", "message"), ignore.order = FALSE)
})

test_that("dq_result() defaults column and threshold to NA_character_", {
  r <- dq_result("QC-04", "Row count", status = "INFO",
                 observed = "100", message = "Info only")
  expect_identical(r$column,    NA_character_)
  expect_identical(r$threshold, NA_character_)
})

test_that("dq_result() stops when status is not one of PASS/WARN/FAIL/INFO", {
  expect_error(
    dq_result("QC-01", "Missing rate", status = "ERROR",
              observed = "x", message = "x"),
    regexp = "status"
  )
})

test_that("dq_result() stops on NULL status", {
  expect_error(
    dq_result("QC-01", "Missing rate", status = NULL,
              observed = "x", message = "x")
  )
})

test_that("dq_result() accepts all four valid status values", {
  for (s in c("PASS", "WARN", "FAIL", "INFO")) {
    r <- dq_result("X-01", "test", status = s, observed = "x", message = "x")
    expect_equal(r$status, s)
  }
})

# -- overall_status() ----------------------------------------------------------

test_that("overall_status() returns FAIL when any result is FAIL", {
  results <- list(
    dq_result("A", "a", status = "PASS", observed = "x", message = "x"),
    dq_result("B", "b", status = "FAIL", observed = "x", message = "x"),
    dq_result("C", "c", status = "WARN", observed = "x", message = "x")
  )
  expect_equal(overall_status(results), "FAIL")
})

test_that("overall_status() returns WARN when no FAIL but some WARN", {
  results <- list(
    dq_result("A", "a", status = "PASS", observed = "x", message = "x"),
    dq_result("B", "b", status = "WARN", observed = "x", message = "x"),
    dq_result("C", "c", status = "INFO", observed = "x", message = "x")
  )
  expect_equal(overall_status(results), "WARN")
})

test_that("overall_status() returns PASS when only PASS and INFO", {
  results <- list(
    dq_result("A", "a", status = "PASS", observed = "x", message = "x"),
    dq_result("B", "b", status = "INFO", observed = "x", message = "x")
  )
  expect_equal(overall_status(results), "PASS")
})

test_that("overall_status() returns INFO on empty list", {
  expect_equal(overall_status(list()), "INFO")
})

# -- infer_col_type() ----------------------------------------------------------

test_that("infer_col_type() returns 'date' for ISO date strings", {
  x <- c("2024-01-01", "2024-06-15", "2023-12-31")
  expect_equal(infer_col_type(x), "date")
})

test_that("infer_col_type() returns 'date' for dd/mm/yyyy format", {
  x <- c("01/01/2024", "15/06/2024", "31/12/2023")
  expect_equal(infer_col_type(x), "date")
})

test_that("infer_col_type() returns 'numeric' when >=90% are numeric", {
  x <- c("1.5", "2.0", "3.1", "abc", rep("4.0", 16))  # 19/20 = 95% numeric
  expect_equal(infer_col_type(x), "numeric")
})

test_that("infer_col_type() returns 'character' when <90% are numeric", {
  x <- c("high", "low", "medium", "1.0", "2.0")  # 40% numeric
  expect_equal(infer_col_type(x), "character")
})

test_that("infer_col_type() returns 'unknown' for all empty/NA", {
  x <- c(NA, "", NA, "")
  expect_equal(infer_col_type(x), "unknown")
})

test_that("infer_col_type() returns 'numeric' for all-NA-except-numeric", {
  x <- c(NA, "1.0", "2.5", NA)
  expect_equal(infer_col_type(x), "numeric")
})

test_that("infer_col_type() respects a custom threshold", {
  # 85% numeric - below default 90%, above custom 80%
  x <- c(rep("1.0", 17), "abc", "def", "ghi")  # 17/20 = 85%
  expect_equal(infer_col_type(x, threshold = 0.90), "character")
  expect_equal(infer_col_type(x, threshold = 0.80), "numeric")
})

test_that("infer_col_type() threshold applies via config in check_inferred_types()", {
  df  <- data.frame(score = c(rep("1.0", 17), "bad", "bad", "bad"),
                    stringsAsFactors = FALSE)
  cfg_strict <- list(rules = list(type_inference_threshold = 0.90))
  cfg_lenient <- list(rules = list(type_inference_threshold = 0.80))
  strict  <- check_inferred_types(df, cfg_strict)
  lenient <- check_inferred_types(df, cfg_lenient)
  expect_equal(strict[[1]]$observed,  "character")
  expect_equal(lenient[[1]]$observed, "numeric")
})

# -- load_config() -------------------------------------------------------------

test_that("load_config() merges rule_overrides over defaults", {
  tmp <- tempdir()
  sub <- file.path(tmp, "cfg_merge_test")
  dir.create(sub, showWarnings = FALSE)
  writeLines(c(
    "default_rules:",
    "  max_missing_rate: 0.05",
    "  min_row_count: 0"
  ), file.path(sub, "dqcheckr.yml"))
  writeLines(c(
    "dataset_name: test_ds",
    "folder: data/",
    "format: csv",
    "rule_overrides:",
    "  max_missing_rate: 0.02"
  ), file.path(sub, "test_ds.yml"))

  cfg <- load_config("test_ds", sub)
  expect_equal(cfg$rules$max_missing_rate, 0.02)
  expect_equal(cfg$rules$min_row_count, 0)
})

test_that("load_config() stops when dqcheckr.yml is missing", {
  tmp <- tempdir()
  sub <- file.path(tmp, "no_global_yml")
  dir.create(sub, showWarnings = FALSE)
  expect_error(load_config("any", sub), regexp = "dqcheckr.yml")
})

test_that("load_config() stops when dataset yml is missing", {
  tmp <- tempdir()
  sub <- file.path(tmp, "no_dataset_yml")
  dir.create(sub, showWarnings = FALSE)
  writeLines(c("default_rules:", "  max_missing_rate: 0.05"),
             file.path(sub, "dqcheckr.yml"))
  expect_error(load_config("nonexistent_ds", sub),
               class = "dqcheckr_missing_file")
})

# -- dq_result() argument hardening (0.2.3, B-05) ---------------------------------

test_that("dq_result() accepts threshold = NULL as absent", {
  r <- dq_result("QC-99", "test", status = "PASS", observed = "ok",
                 threshold = NULL, message = "ok")
  expect_identical(r$threshold, NA_character_)
})

test_that("dq_result() rejects invalid status values with a typed error", {
  expect_error(
    dq_result("QC-99", "t", status = "ERROR", observed = "o", message = "m"),
    class = "dqcheckr_invalid_argument")
  expect_error(
    dq_result("QC-99", "t", status = c("PASS", "FAIL"), observed = "o", message = "m"),
    class = "dqcheckr_invalid_argument")
})

# -- load_config() column_order_severity validation (0.2.3, B-09) -----------------

test_that("load_config() rejects an invalid column_order_severity", {
  tmp <- tempfile("cfg_"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))
  writeLines("default_rules: {}", file.path(tmp, "dqcheckr.yml"))
  writeLines(c("dataset_name: sev_ds",
               "rule_overrides:",
               "  column_order_severity: error"),
             file.path(tmp, "sev_ds.yml"))
  expect_error(load_config("sev_ds", tmp), class = "dqcheckr_invalid_config")
})

test_that("load_config() accepts valid column_order_severity values", {
  tmp <- tempfile("cfg_"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE))
  writeLines("default_rules: {}", file.path(tmp, "dqcheckr.yml"))
  for (sev in c("pass", "warn", "fail", "info", "FAIL")) {
    writeLines(c("dataset_name: sev_ok",
                 "rule_overrides:",
                 sprintf("  column_order_severity: %s", sev)),
               file.path(tmp, "sev_ok.yml"))
    expect_no_error(load_config("sev_ok", tmp))
  }
})

# -- infer_col_type() head-sample shortcut is behaviour-preserving (0.2.3, P-02) --

test_that("infer_col_type() results unchanged with >100 values", {
  dates <- format(seq(as.Date("2020-01-01"), by = "day", length.out = 250), "%Y-%m-%d")
  expect_equal(infer_col_type(dates), "date")
  nums <- as.character(seq_len(250))
  expect_equal(infer_col_type(nums), "numeric")
  # a bad date beyond the head sample still rejects the date classification
  dates_bad <- c(dates, "not-a-date")
  expect_equal(infer_col_type(dates_bad), "character")
  chars <- c(rep("alpha", 150), rep("beta", 150))
  expect_equal(infer_col_type(chars), "character")
})

# -- infer_col_type() anchored date shapes (B-02) --------------------------------
# as.Date() delegates to strptime(), which matches a *prefix*: without an
# anchored shape gate, trailing junk and extra digits were silently accepted as
# dates, so corrupt dates reported clean (QC-06) and numeric id columns lost
# their numeric checks (QC-07/08/11).

test_that("infer_col_type() rejects ISO dates with trailing characters", {
  x <- c("2024-01-15x", "2024-02-20x", "2024-03-25x")
  expect_equal(infer_col_type(x), "character")
})

test_that("infer_col_type() classifies 9-digit ids as numeric, not date", {
  # "202401159" parses under %Y%m%d via prefix match ("20240115") pre-fix.
  x <- c("202401159", "202401160", "202401161", "202401162")
  expect_equal(infer_col_type(x), "numeric")
})

test_that("infer_col_type() rejects mixed-width numeric ids as numeric", {
  x <- c("2024011", "20240115", "202401159", "2024")
  expect_equal(infer_col_type(x), "numeric")
})

test_that("infer_col_type() rejects yyyymmdd values with trailing digits en masse", {
  x <- as.character(seq(202401150, by = 1, length.out = 200))  # all 9-digit
  expect_equal(infer_col_type(x), "numeric")
})

test_that("infer_col_type() keeps the 8-digit valid-date caveat (still 'date')", {
  # Documented caveat: an 8-digit id that is also a valid %Y%m%d date is a date.
  x <- c("20240115", "20240220", "20240325")
  expect_equal(infer_col_type(x), "date")
})

test_that("infer_col_type() treats 8-digit non-calendar ids as numeric", {
  # 8 digits but month/day out of range -> as.Date fails -> numeric (unchanged).
  x <- c("99999999", "88888888", "77777777")
  expect_equal(infer_col_type(x), "numeric")
})

test_that("infer_col_type() still accepts clean dates across all formats", {
  expect_equal(infer_col_type(c("2024-01-15", "2024-02-20")),   "date")  # %Y-%m-%d
  expect_equal(infer_col_type(c("15/01/2024", "20/02/2024")),   "date")  # %d/%m/%Y
  expect_equal(infer_col_type(c("01/25/2024", "02/28/2024")),   "date")  # %m/%d/%Y fallback (day > 12)
  expect_equal(infer_col_type(c("20240115", "20240220")),       "date")  # %Y%m%d
  expect_equal(infer_col_type(c("15-01-2024", "20-02-2024")),   "date")  # %d-%m-%Y
})

test_that("infer_col_type() rejects slashed dates with trailing junk", {
  x <- c("15/01/2024ZZ", "20/02/2024ZZ")
  expect_equal(infer_col_type(x), "character")
})
