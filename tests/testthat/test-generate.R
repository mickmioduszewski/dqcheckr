# generate_dataset_config() (plan step 7): sniff + write. Properties under
# test: generated YAML parses and round-trips the sniffed values; every
# vocabulary key appears exactly once (live xor commented); commented keys are
# absent from the parse but present with defaults in the raw text; positional
# lists are complete; the duplicate-header mechanism works end to end through
# read_dataset(); create-only enforcement leaves an existing file
# byte-identical; generated configs validate green (except packed-FWF, which
# must fail on exactly the TODO check); and generate -> run_dq_check completes.

gen_fixture <- function(content, name = "gen_ds", ext = ".csv") {
  root <- file.path(tempdir(), paste0("gen_", sample.int(1e9, 1)))
  dir.create(root)
  data_file <- file.path(root, paste0(name, ext))
  writeLines(content, data_file)
  # report_output_dir MUST be set: the generated config comments it out, and
  # the relative default would otherwise write reports into the test cwd
  # (CRAN write policy: temp dirs only).
  writeLines(c(sprintf('snapshot_db: "%s/snap.sqlite"', gsub("\\\\", "/", root)),
               sprintf('report_output_dir: "%s"', gsub("\\\\", "/", root))),
             file.path(root, "dqcheckr.yml"))
  list(root = root, data_file = data_file, name = name)
}

gen <- function(fx) suppressMessages(
  generate_dataset_config(fx$data_file, config_dir = fx$root))

# Occurrences of `key` as a live line (^key:) or commented-out line (^# key:).
key_occurrences <- function(lines, key) {
  live      <- sum(grepl(paste0("^", key, ":"), lines))
  commented <- sum(grepl(paste0("^# ", key, ":"), lines))
  c(live = live, commented = commented)
}

# -- every vocabulary key appears exactly once, live xor commented -------------

test_that("every dataset-scope vocabulary key appears exactly once (live xor commented)", {
  fx <- gen_fixture(c("id,amount", "A1,10", "A2,20"))
  on.exit(unlink(fx$root, recursive = TRUE))
  out   <- gen(fx)
  lines <- readLines(out)
  vocab <- .config_vocabulary()
  keys  <- vocab$key[vocab$scope %in% c("dataset", "both")]
  for (k in keys) {
    occ <- key_occurrences(lines, k)
    expect_equal(sum(occ), 1)
  }
})

# -- round-trip of detected values ---------------------------------------------

test_that("the parsed config round-trips the sniffed values for a plain CSV", {
  fx <- gen_fixture(c("id,amount,status", "A1,10,open", "A2,20,closed"))
  on.exit(unlink(fx$root, recursive = TRUE))
  out <- gen(fx)
  cfg <- yaml::read_yaml(out)
  expect_equal(cfg$dataset_name, "gen_ds")
  expect_equal(cfg$format, "csv")
  expect_equal(cfg$encoding, "UTF-8")
  expect_equal(cfg$delimiter, ",")
  expect_equal(cfg$current_file, gsub("\\\\", "/", fx$data_file))
  expect_equal(cfg$expected_columns, c("id", "amount", "status"))
  expect_equal(cfg$column_types,
               list(id = "character", amount = "numeric", status = "character"))
  # Header is clean: col_names/csv_skip stay commented (file's header is used).
  expect_null(cfg$col_names)
  expect_null(cfg$csv_skip)
  expect_null(cfg$key_columns)          # candidates offered commented, never live
})

test_that("commented keys are absent from the parse but present with defaults in the text", {
  fx <- gen_fixture(c("id,amount", "A1,10"))
  on.exit(unlink(fx$root, recursive = TRUE))
  out   <- gen(fx)
  cfg   <- yaml::read_yaml(out)
  lines <- readLines(out)
  for (k in c("description", "folder", "previous_file", "fwf_skip",
              "custom_checks_file", "snapshot_db", "report_output_dir")) {
    expect_null(cfg[[k]])
    expect_equal(unname(key_occurrences(lines, k)["commented"]), 1)
  }
  # Commented defaults show the real runtime defaults, not restatements.
  expect_true(any(grepl(paste0("^# snapshot_db: \"", .default_paths$snapshot_db, "\""),
                        lines)))
  expect_true(any(grepl("^# fwf_skip: 0", lines)))
})

test_that("every key's doc comment is the vocabulary description (single source)", {
  fx <- gen_fixture(c("id,amount", "A1,10"))
  on.exit(unlink(fx$root, recursive = TRUE))
  text  <- paste(readLines(gen(fx)), collapse = "\n")
  vocab <- .config_vocabulary()
  # Spot-probe with the first six words of several descriptions.
  for (k in c("format", "key_columns", "column_rules", "snapshot_db")) {
    d     <- vocab$description[vocab$key == k]
    probe <- paste(strsplit(d, " ")[[1]][1:6], collapse = " ")
    expect_true(grepl(probe, text, fixed = TRUE))
  }
})

# -- duplicate header names, end to end ----------------------------------------

test_that("the duplicate-Amount fixture generates live col_names + csv_skip 1 with was-comments", {
  fx <- gen_fixture(c("Date,Amount,Currency,Amount,Status",
                      "2026-07-01,100.00,AUD,15.00,settled"))
  on.exit(unlink(fx$root, recursive = TRUE))
  out   <- gen(fx)
  cfg   <- yaml::read_yaml(out)
  lines <- readLines(out)
  expect_equal(cfg$col_names, c("Date", "Amount", "Currency", "Amount_2", "Status"))
  expect_equal(cfg$csv_skip, 1)
  expect_true(any(grepl('# was "Amount"', lines, fixed = TRUE)))
  # The positional warning stands guard over the live list.
  expect_true(any(grepl("NEVER comment out a single entry", lines)))
})

test_that("generate -> validate -> read_dataset works end to end for the duplicate fixture", {
  fx <- gen_fixture(c("Date,Amount,Currency,Amount,Status",
                      "2026-07-01,100.00,AUD,15.00,settled",
                      "2026-07-02,200.00,AUD,25.00,settled"))
  on.exit(unlink(fx$root, recursive = TRUE))
  gen(fx)
  v <- validate_config("gen_ds", config_dir = fx$root)
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)
  expect_equal(v$tier, "config+header")
  df <- read_dataset(fx$data_file, load_config("gen_ds", fx$root))
  expect_equal(names(df), c("Date", "Amount", "Currency", "Amount_2", "Status"))
  expect_equal(nrow(df), 2L)            # original header row skipped, not data
})

# -- headerless CSV ------------------------------------------------------------

test_that("a headerless file gets live generated col_names and validates clean", {
  fx <- gen_fixture(c("1,10", "2,20", "3,30"))
  on.exit(unlink(fx$root, recursive = TRUE))
  out <- gen(fx)
  cfg <- yaml::read_yaml(out)
  expect_equal(cfg$col_names, c("col_1", "col_2"))
  expect_null(cfg$csv_skip)             # no header to skip
  v <- validate_config("gen_ds", config_dir = fx$root)
  expect_true(v$valid)
  expect_equal(nrow(v$findings), 0L)
})

# -- positional completeness ---------------------------------------------------

test_that("a live col_names list always covers every physical column", {
  fx <- gen_fixture(c("a,a,b,b,c", "1,2,3,4,5"))   # dups force live col_names
  on.exit(unlink(fx$root, recursive = TRUE))
  cfg <- yaml::read_yaml(gen(fx))
  expect_length(cfg$col_names, 5)
  expect_false(anyDuplicated(cfg$col_names) > 0)
})

# -- FWF -----------------------------------------------------------------------

test_that("a gutter FWF file emits live widths, names, ruler, and validates clean", {
  fx <- gen_fixture(c("A1  100  open ",
                      "B2  200  shut ",
                      "C3  300  open "), ext = ".txt")
  on.exit(unlink(fx$root, recursive = TRUE))
  out   <- gen(fx)
  cfg   <- yaml::read_yaml(out)
  lines <- readLines(out)
  expect_equal(cfg$format, "fwf")
  expect_equal(sum(cfg$fwf_widths), nchar("A1  100  open "))
  expect_equal(cfg$fwf_col_names, c("col_1", "col_2", "col_3"))
  expect_true(any(grepl("Ruler -- character positions", lines)))
  expect_true(any(grepl("^##  A1  100  open ", lines)))   # the sample record itself
  v <- validate_config("gen_ds", config_dir = fx$root)
  expect_true(v$valid)
  expect_equal(v$tier, "config+header")
})

test_that("a packed FWF file emits TODO widths that validation refuses, on exactly that check", {
  fx <- gen_fixture(c("AB12XY0099QQWW2026", "CD34ZW0100RRTT2026"), ext = ".txt")
  on.exit(unlink(fx$root, recursive = TRUE))
  out   <- gen(fx)
  lines <- readLines(out)
  expect_true(any(grepl("^fwf_widths: TODO", lines)))
  expect_true(any(grepl("PACKED", lines)))
  v <- validate_config("gen_ds", config_dir = fx$root)
  expect_false(v$valid)
  errs <- v$findings[v$findings$severity == "error", ]
  expect_equal(errs$key, "fwf_widths")            # only the TODO check fires
  expect_match(errs$message, "TODO placeholder")
  # And the run is blocked with the typed validation abort.
  expect_error(run_dq_check("gen_ds", config_dir = fx$root, open_report = FALSE),
               class = "dqcheckr_validation_error")
})

# -- create-only ---------------------------------------------------------------

test_that("an existing config aborts typed and stays byte-identical", {
  fx <- gen_fixture(c("id,amount", "A1,10"))
  on.exit(unlink(fx$root, recursive = TRUE))
  cfg_path <- file.path(fx$root, "gen_ds.yml")
  writeLines("dataset_name: hand-tuned, do not clobber", cfg_path)
  before <- readBin(cfg_path, "raw", file.size(cfg_path))
  err <- tryCatch(gen(fx), error = function(e) e)
  expect_s3_class(err, "dqcheckr_config_exists")
  expect_match(conditionMessage(err), "never-overwrite")
  expect_identical(readBin(cfg_path, "raw", file.size(cfg_path)), before)
})

test_that("an explicit dataset_name writes under that name; the default is the sanitised filename", {
  fx <- gen_fixture(c("id,amount", "A1,10"), name = "weird name & co")
  on.exit(unlink(fx$root, recursive = TRUE))
  out <- gen(fx)
  expect_equal(basename(out), "weird_name___co.yml")
  out2 <- suppressMessages(generate_dataset_config(
    fx$data_file, config_dir = fx$root, dataset_name = "orders"))
  expect_equal(basename(out2), "orders.yml")
  expect_equal(yaml::read_yaml(out2)$dataset_name, "orders")
})

# -- generated configs validate green across fixture classes -------------------

test_that("generated configs validate with zero findings for every non-packed fixture class", {
  fixtures <- list(
    plain      = list(content = c("id,amount", "A1,10", "A2,20")),
    dup_header = list(content = c("x,x", "1,2")),
    headerless = list(content = c("1,2", "3,4")),
    single_col = list(content = c("id", "A1", "A2")),
    semicolon  = list(content = c("id;note", "A1;hello", "A2;there")),
    fwf_gutter = list(content = c("A1  10", "B2  20"), ext = ".txt")
  )
  for (nm in names(fixtures)) {
    f  <- fixtures[[nm]]
    fx <- gen_fixture(f$content, ext = f$ext %||% ".csv")
    gen(fx)
    v <- validate_config("gen_ds", config_dir = fx$root)
    expect_true(v$valid)
    expect_equal(nrow(v$findings), 0L)
    unlink(fx$root, recursive = TRUE)
  }
})

# -- the full chain ------------------------------------------------------------

test_that("generate -> run_dq_check completes on the fixture with no hand edits", {
  fx <- gen_fixture(c("id,amount,status",
                      "A1,10,open", "A2,20,closed", "A3,30,open"))
  on.exit(unlink(fx$root, recursive = TRUE))
  gen(fx)
  result <- suppressMessages(suppressWarnings(
    run_dq_check("gen_ds", config_dir = fx$root, open_report = FALSE)))
  expect_true(result$status %in% c("PASS", "WARN", "FAIL", "INFO"))
  expect_false(is.null(result$snapshot_id))
  runs <- list_runs("gen_ds", config_dir = fx$root)
  expect_equal(nrow(runs), 1L)
})
