
base_cfg <- function(rules = list(), column_rules = list()) {
  list(rules = rules, column_rules = column_rules, column_types = list())
}

# -- col_threshold() -----------------------------------------------------------

test_that("col_threshold() returns column-level override when present", {
  cfg <- base_cfg(
    rules        = list(max_missing_rate = 0.05),
    column_rules = list(x = list(max_missing_rate = 0.20))
  )
  expect_equal(col_threshold(cfg, "x", "max_missing_rate", 0.05), 0.20)
})

test_that("col_threshold() falls back to rules-level when no column override", {
  cfg <- base_cfg(rules = list(max_missing_rate = 0.10))
  expect_equal(col_threshold(cfg, "y", "max_missing_rate", 0.05), 0.10)
})

test_that("col_threshold() falls back to default when key absent everywhere", {
  cfg <- base_cfg()
  expect_equal(col_threshold(cfg, "z", "max_missing_rate", 0.05), 0.05)
})

test_that("col_threshold() column override wins over rules-level", {
  cfg <- base_cfg(
    rules        = list(max_missing_rate = 0.10),
    column_rules = list(z = list(max_missing_rate = 0.00))
  )
  expect_equal(col_threshold(cfg, "z", "max_missing_rate", 0.05), 0.00)
})

# -- table_threshold() ---------------------------------------------------------

test_that("table_threshold() returns rules value when present", {
  cfg <- base_cfg(rules = list(min_row_count = 100))
  expect_equal(table_threshold(cfg, "min_row_count", 0), 100)
})

test_that("table_threshold() returns default when key absent", {
  cfg <- base_cfg()
  expect_equal(table_threshold(cfg, "min_row_count", 0), 0)
})

test_that("table_threshold() returns NULL default when no default supplied", {
  cfg <- base_cfg()
  expect_null(table_threshold(cfg, "min_row_count"))
})

# -- B-41: `$` partial matching must not resolve a parked column_rules* key -----

test_that("col_threshold() ignores a parked `column_rules*` section (B-41)", {
  # No exact `column_rules` key, but a prefix-extension (a rule set parked by
  # renaming it) exists. `$` would partial-match it and silently drive a 0.0%
  # threshold; exact `[[ ]]` indexing must not.
  cfg <- list(
    column_rules_disabled = list(x = list(max_missing_rate = 0.00)),
    rules = list(max_missing_rate = 0.50)
  )
  expect_null(cfg[["column_rules"]])
  expect_equal(col_threshold(cfg, "x", "max_missing_rate", 0.05), 0.50)
})

test_that("table_threshold() ignores a parked `rules*` section (B-41)", {
  cfg <- list(rules_old = list(min_row_count = 999))   # no exact `rules` key
  expect_equal(table_threshold(cfg, "min_row_count", 0), 0)
})

test_that("a parked column_rules* section does not drive QC-01 (B-41, end-to-end)", {
  cfg_dir <- tempfile("b41_cfg_")
  dir.create(cfg_dir)
  on.exit(unlink(cfg_dir, recursive = TRUE))

  writeLines(c("default_rules:", "  max_missing_rate: 0.50"),
             file.path(cfg_dir, "dqcheckr.yml"))
  # `column_rules_disabled` is a parked (renamed) rule set; the live config has
  # no `column_rules` key. It must not govern any threshold.
  writeLines(c(
    "dataset_name: probe", "format: csv",
    "column_rules_disabled:", "  x:", "    max_missing_rate: 0.00"
  ), file.path(cfg_dir, "probe.yml"))

  cfg <- load_config("probe", cfg_dir)
  expect_null(cfg[["column_rules"]])

  # x is 33% missing: with the parked 0.0% threshold it would FAIL; under the
  # documented global 0.50 it must PASS.
  df  <- data.frame(x = c("a", "", "c"), stringsAsFactors = FALSE)
  res <- check_missing_rate(df, cfg)
  x_res <- Filter(function(r) r$column == "x", res)[[1]]
  expect_equal(x_res$status, "PASS")
  expect_equal(x_res$threshold, "50.0%")
})
