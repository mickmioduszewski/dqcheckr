# validate_config() Tier 1: config-only checks against the vocabulary.
# Covers: clean pass; each violation class individually and in combination;
# a config exercising every vocabulary key validating clean; the unknown-key
# (warn-not-error) policy; the three distinct read-failure conditions; global
# scope checks; identity/file-source/FWF/positional findings; print method.

# Build a config dir; `global`/`dataset` are YAML line vectors.
vcfg <- function(global = 'snapshot_db: "snap.sqlite"',
                 dataset = c('dataset_name: "demo"', 'format: csv',
                             'current_file: "x.csv"'),
                 dataset_name = "demo") {
  dir <- file.path(tempdir(), paste0("vcfg_", sample.int(1e9, 1)))
  dir.create(dir)
  writeLines(global, file.path(dir, "dqcheckr.yml"))
  writeLines(dataset, file.path(dir, paste0(dataset_name, ".yml")))
  dir
}

sev_of  <- function(v, key) v$findings$severity[v$findings$key == key]
msgs_of <- function(v, key) v$findings$message[v$findings$key == key]

# -- clean pass ----------------------------------------------------------------

test_that("a minimal clean config validates with zero findings", {
  dir <- vcfg()
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_s3_class(v, "dqcheckr_validation")
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)
  expect_equal(v$tier, "config-only")
})

test_that("a config exercising EVERY vocabulary key validates clean", {
  # Doubles as a vocabulary-checker completeness proof: every key present,
  # every rule key at a valid placement, all values well-typed.
  rules_yaml <- c(
    "  max_missing_rate: 0.1", "  max_non_numeric_rate: 0.05",
    "  warn_non_numeric_rate: 0.01", "  max_z_score: 4",
    "  iqr_fence_multiplier: 1.5", "  min_row_count: 1",
    "  max_row_count: 99999", "  max_file_size_mb: 500",
    "  max_row_count_change_pct: 0.2", "  max_missing_rate_change_pp: 3",
    "  max_numeric_mean_shift_pct: 0.25", "  max_non_numeric_rate_change_pp: 2",
    "  type_inference_threshold: 0.95", "  flag_new_columns: true",
    "  flag_dropped_columns: false", "  flag_type_changes: true",
    "  flag_column_order_change: false", "  column_order_severity: warn",
    "  missing_rate_change_severity: fail")
  dir <- vcfg(
    global  = c('snapshot_db: "snap.sqlite"', 'report_output_dir: "reports/"',
                "default_rules:", rules_yaml),
    dataset = c(
      'dataset_name: "demo"', "format: csv", 'encoding: "UTF-8"',
      'delimiter: ","', "quote_char: \"'\"",
      "col_names: [id, amount, status]", "csv_skip: 1",
      'current_file: "x.csv"', 'previous_file: "y.csv"',
      # fwf keys are dataset-scope and type-checked even under format csv
      "fwf_widths: [5, 10, 3]", "fwf_col_names: [a, b, c]", "fwf_skip: 0",
      "expected_columns: [id, amount, status]", "key_columns: [id]",
      "column_types:", "  id: character", "  amount: numeric",
      "column_rules:",
      "  amount:",
      "    max_missing_rate: 0.02", "    min_value: 0", "    max_value: 1000000",
      "    max_numeric_mean_shift_pct: 0.1",
      "  status:",
      '    allowed_values: [open, closed]', '    pattern: "^[a-z]+$"',
      "rule_overrides:", rules_yaml,
      'custom_checks_file: "custom.R"',
      'snapshot_db: "snap2.sqlite"', 'report_output_dir: "reports2/"'))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  # 'folder' is deliberately absent (it would conflict with current_file);
  # everything present must produce zero findings.
  expect_equal(nrow(v$findings), 0L)
})

# -- unknown keys: warn, not error ---------------------------------------------

test_that("an unknown top-level key warns (with a did-you-mean) and stays valid", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                          'current_file: "x.csv"', 'delimitter: ";"'))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)                                  # warning, not error
  expect_equal(sev_of(v, "delimitter"), "warning")
  expect_match(msgs_of(v, "delimitter"), "Did you mean 'delimiter'")
})

test_that("an unknown key with no close neighbour warns without a suggestion", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                          'current_file: "x.csv"', 'zzz_totally_novel: 1'))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_equal(sev_of(v, "zzz_totally_novel"), "warning")
  expect_false(grepl("Did you mean", msgs_of(v, "zzz_totally_novel")))
})

test_that("an unknown rule key inside rule maps warns with a suggestion", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                          'current_file: "x.csv"',
                          "rule_overrides:", "  max_missing_rat: 0.1"))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(sev_of(v, "max_missing_rat"), "warning")
  expect_match(msgs_of(v, "max_missing_rat"), "Did you mean 'max_missing_rate'")
})

# -- wrong types and ranges ----------------------------------------------------

test_that("each scalar type violation is an error finding", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: xml',
                          'current_file: "x.csv"',
                          'delimiter: ";;"', "csv_skip: -1", "fwf_skip: 1.5"))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  expect_equal(sev_of(v, "format"),    "error")
  expect_equal(sev_of(v, "delimiter"), "error")
  expect_equal(sev_of(v, "csv_skip"),  "error")
  expect_equal(sev_of(v, "fwf_skip"),  "error")
})

test_that("invalid column_types values are an error finding", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                          'current_file: "x.csv"',
                          "column_types:", "  id: integer"))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_equal(sev_of(v, "column_types"), "error")
  expect_match(msgs_of(v, "column_types"), "integer")
})

test_that("rule value violations are error findings (range, enum, bad regex)", {
  dir <- vcfg(dataset = c(
    'dataset_name: "demo"', 'format: csv', 'current_file: "x.csv"',
    "rule_overrides:",
    "  max_missing_rate: 1.5",                    # out of [0,1]
    "  missing_rate_change_severity: sometimes",  # bad enum
    "column_rules:",
    "  id:",
    '    pattern: "([unclosed"'))                 # invalid regex
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  expect_equal(sev_of(v, "max_missing_rate"), "error")
  expect_equal(sev_of(v, "missing_rate_change_severity"), "error")
  expect_equal(sev_of(v, "pattern"), "error")
  expect_match(msgs_of(v, "pattern"), "not a valid regular expression")
})

test_that("a rules-only key inside column_rules is an error (placement)", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                          'current_file: "x.csv"',
                          "column_rules:", "  id:", "    min_row_count: 5"))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  expect_equal(sev_of(v, "min_row_count"), "error")
  expect_match(msgs_of(v, "min_row_count"), "not valid in column_rules")
})

test_that("a column-only key inside rule_overrides is an error (placement)", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                          'current_file: "x.csv"',
                          "rule_overrides:", '  pattern: "^x$"'))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  expect_equal(sev_of(v, "pattern"), "error")
})

# -- positional-list and FWF findings ------------------------------------------

test_that("fwf format without fwf_widths is an error", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: fwf',
                          'current_file: "x.txt"'))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  expect_equal(sev_of(v, "fwf_widths"), "error")
})

test_that("fwf_col_names / fwf_widths length mismatch is an error naming both lengths", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: fwf',
                          'current_file: "x.txt"',
                          "fwf_widths: [5, 10, 3]", "fwf_col_names: [a, b]"))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  expect_match(msgs_of(v, "fwf_col_names"), "2 name")
  expect_match(msgs_of(v, "fwf_col_names"), "3 width")
  expect_match(msgs_of(v, "fwf_col_names"), "commented out")
})

test_that("the commented-out-a-slot scenario from the design doc is caught", {
  # A user "removes" a column by commenting one fwf_col_names entry: the list
  # shrinks by one and misaligns against fwf_widths. Exactly the sharp-edge
  # trap; must be an error before any run.
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: fwf',
                          'current_file: "x.txt"',
                          "fwf_widths: [4, 8, 2, 6]",
                          "fwf_col_names:",
                          "  - date", "  - amount",
                          "  # - currency   # <- commented out a slot",
                          "  - status"))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  expect_equal(sev_of(v, "fwf_col_names"), "error")
})

test_that("a TODO placeholder in fwf_widths is its own error finding", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: fwf',
                          'current_file: "x.txt"',
                          "fwf_widths: TODO", "fwf_col_names: [a, b]"))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  expect_match(msgs_of(v, "fwf_widths"), "TODO placeholder")
  # No confusing extra length-mismatch finding while widths are TODO.
  expect_length(sev_of(v, "fwf_col_names"), 0)
})

test_that("duplicate names in col_names / fwf_col_names are errors naming the duplicates", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                          'current_file: "x.csv"',
                          "col_names: [date, amount, currency, amount, status]"))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  expect_equal(sev_of(v, "col_names"), "error")
  expect_match(msgs_of(v, "col_names"), "amount")
})

# -- identity and file source --------------------------------------------------

test_that("missing dataset_name warns; mismatched dataset_name warns naming both", {
  dir1 <- vcfg(dataset = c('format: csv', 'current_file: "x.csv"'))
  on.exit(unlink(dir1, recursive = TRUE))
  v1 <- validate_config("demo", config_dir = dir1)
  expect_true(v1$valid)
  expect_equal(sev_of(v1, "dataset_name"), "warning")

  dir2 <- vcfg(dataset = c('dataset_name: "other"', 'format: csv',
                           'current_file: "x.csv"'))
  on.exit(unlink(dir2, recursive = TRUE), add = TRUE)
  v2 <- validate_config("demo", config_dir = dir2)
  expect_equal(sev_of(v2, "dataset_name"), "warning")
  expect_match(msgs_of(v2, "dataset_name"), "other")
  expect_match(msgs_of(v2, "dataset_name"), "demo")
})

test_that("neither current_file nor folder is an error; both is a note", {
  dir1 <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv'))
  on.exit(unlink(dir1, recursive = TRUE))
  v1 <- validate_config("demo", config_dir = dir1)
  expect_false(v1$valid)
  expect_equal(sev_of(v1, "current_file"), "error")

  dir2 <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                           'current_file: "x.csv"', 'folder: "in/"'))
  on.exit(unlink(dir2, recursive = TRUE), add = TRUE)
  v2 <- validate_config("demo", config_dir = dir2)
  expect_true(v2$valid)
  expect_equal(sev_of(v2, "folder"), "note")
})

# -- global scope --------------------------------------------------------------

test_that("a dataset-only key in the global file is a warning finding", {
  dir <- vcfg(global = c('snapshot_db: "snap.sqlite"', 'delimiter: ";"'))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  f <- v$findings[v$findings$key == "delimiter", ]
  expect_equal(f$severity, "warning")
  expect_equal(f$file, "dqcheckr.yml")
  expect_match(f$message, "no effect in the global config")
})

test_that("global default_rules values are validated with the same machinery", {
  dir <- vcfg(global = c('snapshot_db: "snap.sqlite"',
                         "default_rules:", "  max_missing_rate: 2"))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  f <- v$findings[v$findings$key == "max_missing_rate", ]
  expect_equal(f$file, "dqcheckr.yml")
  expect_equal(f$severity, "error")
})

# -- multiple findings reported together ---------------------------------------

test_that("several problems are all reported in one pass, not first-only", {
  dir <- vcfg(dataset = c('format: xml',                    # bad enum (error)
                          'delimitter: ";"',                # unknown (warning)
                          "col_names: [a, b, a]",           # duplicate (error)
                          "rule_overrides:",
                          "  max_missing_rate: 9"))         # range (error)
  # note: no current_file/folder -> one more error; no dataset_name -> warning
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_false(v$valid)
  expect_gte(nrow(v$findings), 6)
  expect_setequal(unique(v$findings$severity), c("error", "warning"))
})

# -- typed read-failure conditions ---------------------------------------------

test_that("missing files abort with dqcheckr_missing_file", {
  dir <- vcfg()
  on.exit(unlink(dir, recursive = TRUE))
  expect_error(validate_config("nope", config_dir = dir),
               class = "dqcheckr_missing_file")
  unlink(file.path(dir, "dqcheckr.yml"))
  expect_error(validate_config("demo", config_dir = dir),
               class = "dqcheckr_missing_file")
})

test_that("an empty config file aborts with dqcheckr_empty_config", {
  dir <- vcfg()
  on.exit(unlink(dir, recursive = TRUE))
  writeLines(c("", "   "), file.path(dir, "demo.yml"))
  expect_error(validate_config("demo", config_dir = dir),
               class = "dqcheckr_empty_config")
})

test_that("unparseable YAML aborts with dqcheckr_config_parse_error", {
  dir <- vcfg()
  on.exit(unlink(dir, recursive = TRUE))
  writeLines('format: [unclosed', file.path(dir, "demo.yml"))
  expect_error(validate_config("demo", config_dir = dir),
               class = "dqcheckr_config_parse_error")
})

test_that("YAML that is not a key map aborts with dqcheckr_invalid_config", {
  dir <- vcfg()
  on.exit(unlink(dir, recursive = TRUE))
  writeLines("just a scalar string", file.path(dir, "demo.yml"))
  expect_error(validate_config("demo", config_dir = dir),
               class = "dqcheckr_invalid_config")
})

# -- checker-registry completeness ---------------------------------------------

test_that("every vocabulary key has a type checker, both tables", {
  expect_setequal(names(.key_checkers),  .config_vocabulary()$key)
  expect_setequal(names(.rule_checkers), .rule_vocabulary()$key)
})

# -- print method --------------------------------------------------------------

test_that("print() shows the verdict, tier, and each finding", {
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                          'current_file: "x.csv"', 'delimitter: ";"'))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  out <- capture.output(print(v))
  expect_match(out[1], "demo")
  expect_match(out[1], "VALID")
  expect_match(out[1], "config-only")
  expect_true(any(grepl("\\[warning\\].*delimitter", out)))

  clean <- validate_config("demo", config_dir = vcfg())
  expect_true(any(grepl("No findings", capture.output(print(clean)))))
})
