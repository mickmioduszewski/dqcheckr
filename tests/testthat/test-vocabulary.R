# The config vocabulary (vocabulary.R): the single source of truth the
# validator checks against and the generators emit from. These tests prove the
# vocabulary and the package agree in BOTH directions -- every consumed key is
# listed, no listed key is fictional -- and that every recorded default is the
# value the code actually applies (asserted against behaviour, not by
# restating literals).

# The explicit walk of every top-level key the package consumes, maintained by
# hand against the source (grep config\[\[ / cfg\[\[ in R/). This list is the
# ground truth the two-way completeness tests compare against.
consumed_top_level <- c(
  # read by read_dataset() / detect_files() (ingest.R)
  "format", "encoding", "delimiter", "quote_char", "col_names", "csv_skip",
  "folder", "current_file", "previous_file",
  "fwf_widths", "fwf_col_names", "fwf_skip",
  # read by the check suite (checks_generic.R, compare.R, snapshot.R)
  "expected_columns", "key_columns", "column_types", "column_rules",
  # read by load_config() / run_custom_checks() / drift.R
  "rule_overrides", "custom_checks_file", "snapshot_db", "report_output_dir",
  "default_rules"
)

# Keys in the vocabulary that no R code reads directly, with the reason.
documented_exceptions <- c(
  dataset_name = "identity key: matched to the config filename; read as a function argument, not from the parsed YAML"
)

# The explicit walk of every rule key the package consumes.
consumed_rule_keys <- c(
  # col_threshold()/table_threshold() sites
  "max_missing_rate", "max_non_numeric_rate", "warn_non_numeric_rate",
  "max_z_score", "iqr_fence_multiplier",
  "min_row_count", "max_row_count", "max_file_size_mb",
  # config[["rules"]][[...]] sites
  "max_row_count_change_pct", "max_missing_rate_change_pp",
  "max_numeric_mean_shift_pct", "max_non_numeric_rate_change_pp",
  "type_inference_threshold", "flag_new_columns", "flag_dropped_columns",
  "flag_type_changes", "flag_column_order_change",
  "column_order_severity", "missing_rate_change_severity",
  # column_rules entry keys (checks_generic.R: allowed/pattern/bounds checks)
  "allowed_values", "pattern", "min_value", "max_value"
)

# -- two-way completeness ------------------------------------------------------

test_that("every consumed top-level key appears in the vocabulary", {
  vocab <- .config_vocabulary()
  missing <- setdiff(consumed_top_level, vocab$key)
  expect_length(missing, 0)
})

test_that("no vocabulary key is unconsumed (except documented exceptions)", {
  vocab <- .config_vocabulary()
  extra <- setdiff(vocab$key, c(consumed_top_level, names(documented_exceptions)))
  expect_length(extra, 0)
})

test_that("every consumed rule key appears in the rule vocabulary, and vice versa", {
  rules <- .rule_vocabulary()
  expect_length(setdiff(consumed_rule_keys, rules$key), 0)
  expect_length(setdiff(rules$key, consumed_rule_keys), 0)
})

test_that("vocabulary keys are unique within each table", {
  expect_false(any(duplicated(.config_vocabulary()$key)))
  expect_false(any(duplicated(.rule_vocabulary()$key)))
})

# -- structural properties -----------------------------------------------------

test_that("positional keys are exactly col_names, fwf_widths, fwf_col_names", {
  expect_setequal(.positional_keys(), c("col_names", "fwf_widths", "fwf_col_names"))
})

test_that("scope, required, and placement values are from their closed sets", {
  vocab <- .config_vocabulary()
  expect_true(all(vocab$scope %in% c("dataset", "global", "both")))
  expect_true(all(vocab$required %in% c("no", "conditional")))
  rules <- .rule_vocabulary()
  expect_true(all(rules$placement %in% c("rules", "column", "both")))
})

test_that("every description is non-empty, in both tables", {
  expect_true(all(nzchar(trimws(.config_vocabulary()$description))))
  expect_true(all(nzchar(trimws(.rule_vocabulary()$description))))
})

test_that("has_default agrees with default in both tables", {
  for (tab in list(.config_vocabulary(), .rule_vocabulary())) {
    expect_equal(tab$has_default,
                 !vapply(tab$default, is.null, logical(1)))
  }
})

test_that("global scope holds exactly the shared/global keys", {
  vocab <- .config_vocabulary()
  expect_setequal(vocab$key[vocab$scope %in% c("global", "both")],
                  c("snapshot_db", "report_output_dir", "default_rules"))
})

# -- defaults agree with the constants the code reads --------------------------

test_that("vocabulary defaults are the runtime constants, not restated copies", {
  vocab <- .config_vocabulary()
  dflt  <- function(k) vocab$default[[which(vocab$key == k)]]
  expect_identical(dflt("format"),            .default_read$format)
  expect_identical(dflt("encoding"),          .default_read$encoding)
  expect_identical(dflt("delimiter"),         .default_read$delimiter)
  expect_identical(dflt("quote_char"),        .default_read$quote_char)
  expect_identical(dflt("csv_skip"),          .default_read$csv_skip)
  expect_identical(dflt("fwf_skip"),          .default_read$fwf_skip)
  expect_identical(dflt("snapshot_db"),       .default_paths$snapshot_db)
  expect_identical(dflt("report_output_dir"), .default_paths$report_output_dir)

  rules <- .rule_vocabulary()
  rdflt <- function(k) rules$default[[which(rules$key == k)]]
  for (k in names(.default_qc_rules))
    expect_identical(rdflt(k), .default_qc_rules[[k]])
  for (k in names(.default_comparison_rules))
    expect_identical(rdflt(k), .default_comparison_rules[[k]])
})

# -- defaults agree with actual behaviour (not just with the constants) --------

test_that("read_dataset() applies the vocabulary's format/delimiter/quote/skip defaults", {
  # A file exercising delimiter "," quote '"' and csv_skip 0 all at once: if
  # any default differed, the parse shape would change.
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f))
  writeLines(c('a,b', '"x,1",2'), f)
  df <- read_dataset(f, list())          # empty config: pure defaults
  expect_equal(names(df), c("a", "b"))   # delimiter "," + header row (csv_skip 0)
  expect_equal(df$a, "x,1")              # quote_char '"' honoured
  expect_equal(nrow(df), 1L)
})

test_that("read_dataset() applies the UTF-8 encoding default", {
  f <- tempfile(fileext = ".csv")
  on.exit(unlink(f))
  writeBin(charToRaw("a\nCafé\n"), f)    # UTF-8 bytes, no encoding declared
  df <- read_dataset(f, list())
  expect_equal(df$a, "Café")
})

test_that("read_fwf path applies the fwf_skip default of 0", {
  f <- tempfile(fileext = ".txt")
  on.exit(unlink(f))
  writeLines(c("AB12", "CD34"), f)
  df <- read_dataset(f, list(format = "fwf", fwf_widths = c(2, 2)))
  expect_equal(nrow(df), 2L)             # no lines skipped by default
})

test_that("QC-01 applies the max_missing_rate default from the vocabulary", {
  rules <- .rule_vocabulary()
  dflt  <- rules$default[[which(rules$key == "max_missing_rate")]]
  # 1 missing in 10 = 0.10: above the 0.05 default -> FAIL; 0 in 10 -> PASS.
  df_bad  <- data.frame(x = c(rep("v", 9), NA), stringsAsFactors = FALSE)
  df_good <- data.frame(x = rep("v", 10),       stringsAsFactors = FALSE)
  cfg     <- list(rules = list())        # nothing configured: default governs
  expect_equal(check_missing_rate(df_bad,  cfg)[[1]]$status, "FAIL")
  expect_equal(check_missing_rate(df_good, cfg)[[1]]$status, "PASS")
  expect_true(0.10 > dflt && 0 <= dflt)  # the boundary the two cases straddle
})

test_that("type inference applies the 0.90 threshold default", {
  # 9 of 10 numeric = 0.90 -> numeric at the default; 8 of 10 = 0.80 -> character.
  expect_equal(infer_col_type(c(as.character(1:9), "x")), "numeric")
  expect_equal(infer_col_type(c(as.character(1:8), "x", "y")), "character")
})

test_that("min_row_count default of 0 disables the minimum-rows check", {
  # One data row, nothing configured: with the default of 0 the minimum check
  # reports itself disabled and nothing fails. (Zero rows is NOT the case to
  # test here -- an empty delivery always FAILs QC-14 unconditionally.)
  df  <- data.frame(x = "v", stringsAsFactors = FALSE)
  res <- check_min_row_count(df, list(rules = list()))
  statuses <- vapply(res, `[[`, character(1), "status")
  expect_false("FAIL" %in% statuses)
  msgs <- vapply(res, `[[`, character(1), "message")
  expect_true(any(grepl("disabled", msgs)))
})

# -- keys with no default are genuinely optional-off ---------------------------

test_that("rules without defaults leave their checks un-run when unset", {
  df  <- data.frame(x = as.character(1:20), stringsAsFactors = FALSE)
  cfg <- list(rules = list())
  # max_z_score / iqr_fence_multiplier unset: outlier check emits no result
  # for the column (or only non-FAIL results).
  res <- check_outliers(df, cfg)
  statuses <- vapply(res, `[[`, character(1), "status")
  expect_false("FAIL" %in% statuses)
  # max_row_count unset: 20 rows cannot fail an upper bound.
  res2 <- check_min_row_count(df, cfg)
  expect_false("FAIL" %in% vapply(res2, `[[`, character(1), "status"))
})
