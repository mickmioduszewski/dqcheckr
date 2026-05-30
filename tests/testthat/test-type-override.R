cfg_base <- function(column_types = list(), column_rules = list()) {
  list(
    rules        = list(type_inference_threshold = 0.90,
                        max_missing_rate         = 0.05,
                        max_non_numeric_rate     = 0.01),
    column_types = column_types,
    column_rules = column_rules
  )
}

# --- resolve_col_type() -------------------------------------------------------

test_that("resolve_col_type returns inferred type when no override", {
  cfg <- cfg_base()
  expect_equal(resolve_col_type("x", c("1", "2", "3"), cfg), "numeric")
  expect_equal(resolve_col_type("x", c("a", "b", "c"), cfg), "character")
})

test_that("resolve_col_type returns override regardless of values", {
  cfg <- cfg_base(column_types = list(phone = "character"))
  expect_equal(resolve_col_type("phone", c("0412345678", "0298765432"), cfg),
               "character")
})

test_that("resolve_col_type override works for numeric and date", {
  cfg_num  <- cfg_base(column_types = list(code = "numeric"))
  cfg_date <- cfg_base(column_types = list(ts   = "date"))
  expect_equal(resolve_col_type("code", c("abc", "def"), cfg_num),  "numeric")
  expect_equal(resolve_col_type("ts",   c("abc", "def"), cfg_date), "date")
})

# --- load_config() validation -------------------------------------------------

test_that("load_config aborts on invalid column_types value", {
  tmp <- tempdir()
  writeLines(c(
    'snapshot_db: "snap.sqlite"',
    'report_output_dir: "reports/"',
    'default_rules:',
    '  max_missing_rate: 0.05'
  ), file.path(tmp, "dqcheckr.yml"))
  writeLines(c(
    'dataset_name: "test"',
    paste0('current_file: "', system.file("demonstrations/data/starwars.csv",
                                           package = "dqcheckr"), '"'),
    'format: csv',
    'encoding: "UTF-8"',
    'delimiter: ","',
    'column_types:',
    '  BondNumber: integer'
  ), file.path(tmp, "test.yml"))
  expect_error(load_config("test", tmp), "Invalid column_types")
})

# --- QC-06: inferred type report ----------------------------------------------

test_that("QC-06 reports overridden type with '(overridden)' in message", {
  cfg <- cfg_base(column_types = list(phone = "character"))
  df  <- data.frame(phone = c("0412345678", "0298765432"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-06" && r$column == "phone",
                check_inferred_types(df, cfg))
  expect_equal(res[[1]]$observed, "character")
  expect_match(res[[1]]$message, "overridden")
})

test_that("QC-06 does not say overridden for non-overridden columns", {
  cfg <- cfg_base()
  df  <- data.frame(name = c("Alice", "Bob"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-06" && r$column == "name",
                check_inferred_types(df, cfg))
  expect_false(grepl("overridden", res[[1]]$message))
})

# --- QC-07: numeric stats skips character-forced columns ----------------------

test_that("QC-07 skips a column forced to character", {
  cfg <- cfg_base(column_types = list(phone = "character"))
  # phone is all digits — would be inferred numeric without override
  df  <- data.frame(phone = c("0412345678", "0298765432"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-07", check_numeric_stats(df, cfg))
  expect_length(res, 0)
})

test_that("QC-07 runs on a column forced to numeric", {
  cfg <- cfg_base(column_types = list(code = "numeric"))
  df  <- data.frame(code = c("10", "20", "30"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-07", check_numeric_stats(df, cfg))
  expect_length(res, 1)
})

# --- QC-08: distinct counts skips numeric and date forced columns -------------

test_that("QC-08 skips numeric-forced columns", {
  cfg <- cfg_base(column_types = list(amt = "numeric"))
  df  <- data.frame(amt = c("100", "200"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-08" && r$column == "amt",
                check_distinct_counts(df, cfg))
  expect_length(res, 0)
})

test_that("QC-08 skips date-forced columns", {
  cfg <- cfg_base(column_types = list(ts = "date"))
  df  <- data.frame(ts = c("2024-01-01", "2024-06-01"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-08" && r$column == "ts",
                check_distinct_counts(df, cfg))
  expect_length(res, 0)
})

test_that("QC-08 runs on character-forced columns", {
  cfg <- cfg_base(column_types = list(code = "character"))
  df  <- data.frame(code = c("10", "20", "10"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-08" && r$column == "code",
                check_distinct_counts(df, cfg))
  expect_length(res, 1)
  expect_equal(res[[1]]$observed, "2")
})

# --- QC-11: non-numeric skips character-forced columns -----------------------

test_that("QC-11 skips a column forced to character", {
  cfg <- cfg_base(column_types = list(unit = "character"))
  # mix of digits and alpha — QC-11 would fire if inferred numeric
  df  <- data.frame(unit = c("1", "2", "3A", "Ground"), stringsAsFactors = FALSE)
  res <- Filter(\(r) r$check_id == "QC-11", check_non_numeric(df, cfg))
  expect_length(res, 0)
})

# --- CP-02: type override stabilises type comparison -------------------------

test_that("CP-02 no WARN when override keeps type stable", {
  # Without override: col would flip numeric<->character as non-numeric rate changes
  cfg <- cfg_base(column_types = list(unit = "character"))
  # both deliveries forced to character — no type change possible
  curr <- data.frame(unit = c("1", "2", "3A"), stringsAsFactors = FALSE)
  prev <- data.frame(unit = c("1", "2", "3"),  stringsAsFactors = FALSE)
  res  <- Filter(\(r) r$check_id == "CP-02", compare_schema(curr, prev, cfg))
  expect_equal(res[[1]]$status, "PASS")
})

# --- CP-04: mean shift skips character-forced columns ------------------------

test_that("CP-04 skips a column forced to character", {
  cfg  <- cfg_base(column_types = list(phone = "character"))
  curr <- data.frame(phone = c("0412345678", "0298765432"), stringsAsFactors = FALSE)
  prev <- data.frame(phone = c("0400000000", "0200000000"), stringsAsFactors = FALSE)
  res  <- Filter(\(r) r$check_id == "CP-04", compare_numeric_mean(curr, prev, cfg))
  expect_length(res, 0)
})

# --- CP-07: non-numeric rate change skips character-forced columns -----------

test_that("CP-07 skips a column forced to character", {
  cfg  <- cfg_base(column_types = list(unit = "character"))
  curr <- data.frame(unit = c("1", "2", "3A", "4A"), stringsAsFactors = FALSE)
  prev <- data.frame(unit = c("1", "2", "3",  "4"),  stringsAsFactors = FALSE)
  res  <- Filter(\(r) r$check_id == "CP-07",
                 compare_non_numeric_rate(curr, prev, cfg))
  expect_length(res, 0)
})

# --- compute_col_stats: stores overridden type --------------------------------

test_that("compute_col_stats stores overridden type in inferred_type row", {
  cfg <- cfg_base(column_types = list(phone = "character"))
  df  <- data.frame(phone = c("0412345678", "0298765432"), stringsAsFactors = FALSE)
  cs  <- compute_col_stats(df, cfg, list())
  row <- cs[cs$column_name == "phone" & cs$dq_check == "inferred_type", ]
  expect_equal(row$value, "character")
})

test_that("compute_col_stats does not add numeric stats for character-forced column", {
  cfg <- cfg_base(column_types = list(phone = "character"))
  df  <- data.frame(phone = c("0412345678", "0298765432"), stringsAsFactors = FALSE)
  cs  <- compute_col_stats(df, cfg, list())
  expect_equal(nrow(cs[cs$column_name == "phone" &
                          cs$dq_check == "numeric_mean", ]), 0L)
})
