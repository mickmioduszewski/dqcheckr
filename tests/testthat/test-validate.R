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
      'dataset_name: "demo"', 'description: "exercises every key"',
      "format: csv", 'encoding: "UTF-8"',
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

test_that("change-thresholds accept legacy >1 values; suspicious raw-percent values warn; negatives error", {
  # 1.5 = tolerate +150%: legal, GUI-written, must validate clean.
  dir <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                          'current_file: "x.csv"',
                          "rule_overrides:",
                          "  max_numeric_mean_shift_pct: 1.5",
                          "  max_row_count_change_pct: 2"))
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)

  # 20 is almost certainly a raw percentage: warning, not a block.
  dir2 <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                           'current_file: "x.csv"',
                           "rule_overrides:", "  max_numeric_mean_shift_pct: 20"))
  on.exit(unlink(dir2, recursive = TRUE), add = TRUE)
  v2 <- validate_config("demo", config_dir = dir2)
  expect_true(v2$valid)
  expect_equal(sev_of(v2, "max_numeric_mean_shift_pct"), "warning")
  expect_match(msgs_of(v2, "max_numeric_mean_shift_pct"), "raw percentage")

  # Negative is a genuine error.
  dir3 <- vcfg(dataset = c('dataset_name: "demo"', 'format: csv',
                           'current_file: "x.csv"',
                           "rule_overrides:", "  max_row_count_change_pct: -0.1"))
  on.exit(unlink(dir3, recursive = TRUE), add = TRUE)
  v3 <- validate_config("demo", config_dir = dir3)
  expect_false(v3$valid)
  expect_equal(sev_of(v3, "max_row_count_change_pct"), "error")
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

test_that("an empty DATASET config aborts with dqcheckr_empty_config", {
  dir <- vcfg()
  on.exit(unlink(dir, recursive = TRUE))
  writeLines(c("", "   "), file.path(dir, "demo.yml"))
  expect_error(validate_config("demo", config_dir = dir),
               class = "dqcheckr_empty_config")
})

test_that("an empty or comments-only GLOBAL config is tolerated with a warning (all defaults)", {
  # load_config() has always tolerated this (every key defaults); validation
  # must not turn a working deployment into one that cannot run at all.
  for (content in list(character(0), c("# all defaults", "# nothing set"))) {
    dir <- vcfg()
    writeLines(content, file.path(dir, "dqcheckr.yml"))
    v <- validate_config("demo", config_dir = dir)
    expect_true(v$valid)
    expect_equal(sum(grepl("empty or comments-only", v$findings$message)), 1)
    expect_equal(v$findings$severity[grepl("empty or comments-only",
                                           v$findings$message)], "warning")
    unlink(dir, recursive = TRUE)
  }
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

# ==============================================================================
# Tier 2: header-only cross-check against the delivery file
# ==============================================================================

# A config dir whose dataset config points at a real delivery file written
# from `content` lines. Extra dataset YAML lines via `dataset`.
vcfg2 <- function(content, dataset = character(), format = "csv",
                  file_ext = ".csv") {
  data_file <- tempfile(fileext = file_ext)
  writeLines(content, data_file)
  dir <- vcfg(dataset = c('dataset_name: "demo"',
                          sprintf("format: %s", format),
                          sprintf('current_file: "%s"',
                                  gsub("\\\\", "/", data_file)),
                          dataset))
  attr(dir, "data_file") <- data_file
  dir
}
cleanup2 <- function(dir) unlink(c(attr(dir, "data_file"), dir), recursive = TRUE)

test_that("a matched CSV fixture passes tier 2 with zero findings and tier config+header", {
  dir <- vcfg2("id,amount,status", dataset = c(
    "expected_columns: [id, amount, status]", "key_columns: [id]",
    "column_types:", "  amount: numeric",
    "column_rules:", "  amount:", "    min_value: 0"))
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)
  expect_equal(v$tier, "config+header")
  expect_null(v$tier2_skipped)
})

test_that("col_names shorter than the delivery warns naming both counts (drift must still run)", {
  dir <- vcfg2(c("Date,Amount,Currency,Amount,Status", "1,2,3,4,5"),
               dataset = c("col_names: [date, amount, currency, status]",
                           "csv_skip: 1"))
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)                       # Tier-2 policy: warn, never block
  expect_equal(sev_of(v, "col_names"), "warning")
  expect_match(msgs_of(v, "col_names"), "4 name")
  expect_match(msgs_of(v, "col_names"), "5 column")
  expect_match(msgs_of(v, "col_names"), "commented out")
})

test_that("col_names longer than the delivery also warns", {
  dir <- vcfg2("a,b", dataset = "col_names: [x, y, z]")
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  expect_equal(sev_of(v, "col_names"), "warning")
  expect_match(msgs_of(v, "col_names"), "3 name")
  expect_match(msgs_of(v, "col_names"), "2 column")
})

test_that("csv_skip + col_names counts against the first data line, not the replaced header", {
  # Physical line 1 (old header) has 5 fields and is skipped; the matching
  # col_names list of 5 must validate clean.
  dir <- vcfg2(c("Date,Amount,Currency,Amount,Status", "1,2,3,4,5"),
               dataset = c("col_names: [date, amt_gross, ccy, amt_ref, status]",
                           "csv_skip: 1"))
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)
})

test_that("each name cross-check fires individually with its severity", {
  dir <- vcfg2("id,amount", dataset = "key_columns: [custid]")
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)                        # Tier-2 policy: warn, never block
  expect_equal(sev_of(v, "key_columns"), "warning")
  expect_match(msgs_of(v, "key_columns"), "custid")

  dir2 <- vcfg2("id,amount", dataset = "expected_columns: [id, amount, ref]")
  on.exit(cleanup2(dir2), add = TRUE)
  v2 <- validate_config("demo", config_dir = dir2)
  expect_true(v2$valid)                       # expected_columns: warning only
  expect_equal(sev_of(v2, "expected_columns"), "warning")
  expect_match(msgs_of(v2, "expected_columns"), "ref")

  dir3 <- vcfg2("id,amount", dataset = c("column_types:", "  ghost: numeric"))
  on.exit(cleanup2(dir3), add = TRUE)
  v3 <- validate_config("demo", config_dir = dir3)
  expect_equal(sev_of(v3, "column_types"), "warning")

  dir4 <- vcfg2("id,amount",
                dataset = c("column_rules:", "  ghost:", "    min_value: 0"))
  on.exit(cleanup2(dir4), add = TRUE)
  v4 <- validate_config("demo", config_dir = dir4)
  expect_equal(sev_of(v4, "column_rules"), "warning")
})

test_that("name checks use col_names as the effective set when supplied", {
  # File header says A,B but col_names renames to id,amount: key_columns must
  # be checked against the renamed set, not the raw header.
  dir <- vcfg2(c("A,B", "1,2"),
               dataset = c("col_names: [id, amount]", "csv_skip: 1",
                           "key_columns: [id]"))
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)
})

test_that("the header parse honours a non-default delimiter and quote", {
  # ';'-separated with a quoted field containing ';' -- a comma-parse or
  # quote-blind parse would get the column count wrong.
  dir <- vcfg2("'id;x';amount;status",
               dataset = c('delimiter: ";"', "quote_char: \"'\"",
                           "expected_columns: [\"id;x\", amount, status]"))
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)
})

test_that("a UTF-8 BOM does not corrupt the first column's name", {
  data_file <- tempfile(fileext = ".csv")
  writeBin(c(charToRaw("\xEF\xBB\xBF"), charToRaw("id,amount\n1,2\n")), data_file)
  dir <- vcfg(dataset = c('dataset_name: "demo"', "format: csv",
                          sprintf('current_file: "%s"',
                                  gsub("\\\\", "/", data_file)),
                          "key_columns: [id]"))
  on.exit(unlink(c(data_file, dir), recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)                        # BOM stripped: 'id' matches
  expect_equal(nrow(v$findings), 0L)
})

test_that("folder mode resolves the newest file for the header check", {
  folder <- file.path(tempdir(), paste0("t2_folder_", sample.int(1e9, 1)))
  dir.create(folder)
  old <- file.path(folder, "old.csv"); new <- file.path(folder, "new.csv")
  writeLines("a,b",    old)                   # 2 columns
  writeLines("a,b,c",  new)                   # 3 columns -- the newest
  Sys.setFileTime(old, Sys.time() - 3600)
  dir <- vcfg(dataset = c('dataset_name: "demo"', "format: csv",
                          sprintf('folder: "%s"', gsub("\\\\", "/", folder)),
                          "col_names: [x, y, z]"))   # matches new.csv only
  on.exit(unlink(c(folder, dir), recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)
})

# -- FWF record length ---------------------------------------------------------

test_that("fwf widths summing over or under the record length warns (Tier-2 policy)", {
  dir <- vcfg2("AB12XY", format = "fwf", file_ext = ".txt",
               dataset = "fwf_widths: [2, 2, 4]")     # sum 8 > 6
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(sev_of(v, "fwf_widths"), "warning")
  expect_match(msgs_of(v, "fwf_widths"), "sum \\(8\\) exceeds the record length \\(6\\)")

  dir2 <- vcfg2("AB12XY", format = "fwf", file_ext = ".txt",
                dataset = "fwf_widths: [2, 2]")       # sum 4 < 6
  on.exit(cleanup2(dir2), add = TRUE)
  v2 <- validate_config("demo", config_dir = dir2)
  expect_true(v2$valid)
  expect_equal(sev_of(v2, "fwf_widths"), "warning")
  expect_match(msgs_of(v2, "fwf_widths"), "short of the record length \\(6\\)")
})

test_that("an exact fwf width sum is clean, and CRLF line endings do not skew it", {
  data_file <- tempfile(fileext = ".txt")
  writeBin(charToRaw("AB12XY\r\nCD34ZW\r\n"), data_file)  # CRLF: record is 6, not 7
  dir <- vcfg(dataset = c('dataset_name: "demo"', "format: fwf",
                          sprintf('current_file: "%s"',
                                  gsub("\\\\", "/", data_file)),
                          "fwf_widths: [2, 2, 2]",
                          "fwf_col_names: [a, n, z]",
                          "key_columns: [a]"))
  on.exit(unlink(c(data_file, dir), recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)
  expect_equal(v$tier, "config+header")
})

test_that("fwf_skip is honoured before measuring the record", {
  dir <- vcfg2(c("REPORT HEADER LINE LONGER THAN DATA", "AB12"),
               format = "fwf", file_ext = ".txt",
               dataset = c("fwf_widths: [2, 2]", "fwf_skip: 1"))
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)                        # measured against "AB12", not the banner
  expect_equal(nrow(v$findings), 0L)
})

test_that("FWF without fwf_col_names skips name checks rather than misfiring", {
  dir <- vcfg2("AB12", format = "fwf", file_ext = ".txt",
               dataset = c("fwf_widths: [2, 2]", "key_columns: [id]"))
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  # Effective names unknown: the key_columns cross-check cannot run, and must
  # not produce a false finding.
  expect_length(sev_of(v, "key_columns"), 0)
})

# -- skip semantics ------------------------------------------------------------

test_that("an unresolvable delivery skips tier 2 with a stated reason, not an error", {
  dir <- vcfg()                               # current_file: "x.csv" (absent)
  on.exit(unlink(dir, recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(v$tier, "config-only")
  expect_match(v$tier2_skipped, "x.csv")
  out <- capture.output(print(v))
  expect_true(any(grepl("Header cross-check skipped", out)))
})

test_that("an empty folder skips tier 2 with a stated reason", {
  folder <- file.path(tempdir(), paste0("t2_empty_", sample.int(1e9, 1)))
  dir.create(folder)
  dir <- vcfg(dataset = c('dataset_name: "demo"', "format: csv",
                          sprintf('folder: "%s"', gsub("\\\\", "/", folder))))
  on.exit(unlink(c(folder, dir), recursive = TRUE))
  v <- validate_config("demo", config_dir = dir)
  expect_equal(v$tier, "config-only")
  expect_match(v$tier2_skipped, "No files")
})

# -- boundedness ---------------------------------------------------------------

test_that("tier 2 reads only the head: a malformed multi-thousand-line body is never parsed", {
  # Body lines carry unclosed quotes and ragged fields that a whole-file parse
  # would choke on (or at least slow down); only the header line is read, so
  # validation stays clean and instant.
  dir <- vcfg2(c("id,amount",
                 rep('"unclosed,quote,and,ragged,fields,,,,x', 5000)),
               dataset = "key_columns: [id]")
  on.exit(cleanup2(dir))
  v <- validate_config("demo", config_dir = dir)
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)
  expect_equal(v$tier, "config+header")
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
