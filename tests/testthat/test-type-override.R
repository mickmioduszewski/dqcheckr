library(testthat)
library(dqcheckr)

cfg_base <- function(column_types = list(), column_rules = list()) {
  list(
    rules        = list(type_inference_threshold = 0.90,
                        max_missing_rate         = 0.05,
                        max_non_numeric_rate     = 0.01),
    column_types = column_types,
    column_rules = column_rules
  )
}

# -- resolve_col_type() --------------------------------------------------------

test_that("resolve_col_type() returns inferred type when no override", {
  cfg <- cfg_base()
  expect_equal(resolve_col_type("x", c("1", "2", "3"), cfg), "numeric")
  expect_equal(resolve_col_type("x", c("a", "b", "c"), cfg), "character")
})

test_that("resolve_col_type() returns override regardless of values", {
  cfg <- cfg_base(column_types = list(phone = "character"))
  expect_equal(resolve_col_type("phone", c("0412345678", "0298765432"), cfg),
               "character")
})

test_that("resolve_col_type() override works for numeric and date", {
  cfg_num  <- cfg_base(column_types = list(code = "numeric"))
  cfg_date <- cfg_base(column_types = list(ts   = "date"))
  expect_equal(resolve_col_type("code", c("abc", "def"), cfg_num),  "numeric")
  expect_equal(resolve_col_type("ts",   c("abc", "def"), cfg_date), "date")
})

# -- load_config() validation of column_types ----------------------------------

test_that("load_config() aborts on invalid column_types value", {
  tmp <- withr::local_tempdir()
  writeLines(c(
    'snapshot_db: "snap.sqlite"',
    'report_output_dir: "reports/"',
    'default_rules:',
    '  max_missing_rate: 0.05'
  ), file.path(tmp, "dqcheckr.yml"))
  writeLines(c(
    'dataset_name: "test"',
    paste0('current_file: "',
           system.file("demonstrations/data/starwars.csv", package = "dqcheckr"),
           '"'),
    'format: csv',
    'encoding: "UTF-8"',
    'delimiter: ","',
    'column_types:',
    '  BondNumber: integer'
  ), file.path(tmp, "test.yml"))
  expect_error(load_config("test", tmp), "Invalid column_types")
})

test_that("load_config() accepts valid column_types", {
  tmp <- withr::local_tempdir()
  writeLines(c(
    'snapshot_db: "snap.sqlite"',
    'report_output_dir: "reports/"',
    'default_rules:',
    '  max_missing_rate: 0.05'
  ), file.path(tmp, "dqcheckr.yml"))
  writeLines(c(
    'dataset_name: "test"',
    paste0('current_file: "',
           system.file("demonstrations/data/starwars.csv", package = "dqcheckr"),
           '"'),
    'format: csv',
    'encoding: "UTF-8"',
    'delimiter: ","',
    'column_types:',
    '  name: character',
    '  height: numeric'
  ), file.path(tmp, "test.yml"))
  cfg <- load_config("test", tmp)
  expect_equal(cfg$column_types$name,   "character")
  expect_equal(cfg$column_types$height, "numeric")
})

test_that("load_config() inherits snapshot_db and report_output_dir from global", {
  tmp <- withr::local_tempdir()
  writeLines(c(
    'snapshot_db: "global_snap.sqlite"',
    'report_output_dir: "global_reports/"',
    'default_rules:',
    '  max_missing_rate: 0.05'
  ), file.path(tmp, "dqcheckr.yml"))
  writeLines(c(
    'dataset_name: "test"',
    paste0('current_file: "',
           system.file("demonstrations/data/starwars.csv", package = "dqcheckr"),
           '"'),
    'format: csv',
    'encoding: "UTF-8"',
    'delimiter: ","'
  ), file.path(tmp, "test.yml"))
  cfg <- load_config("test", tmp)
  expect_equal(cfg$snapshot_db,       "global_snap.sqlite")
  expect_equal(cfg$report_output_dir, "global_reports/")
})
