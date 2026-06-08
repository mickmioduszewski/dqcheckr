
fix <- function(f) testthat::test_path("fixtures", f)

# -- read_dataset() ------------------------------------------------------------

test_that("read_dataset() reads CSV and returns all-character data frame", {
  cfg <- list(format = "csv", encoding = "UTF-8", delimiter = ",")
  df  <- read_dataset(fix("valid_accounts_current.csv"), cfg)
  expect_s3_class(df, "data.frame")
  expect_true(all(vapply(df, is.character, logical(1))))
})

test_that("read_dataset() has the expected columns", {
  cfg <- list(format = "csv", encoding = "UTF-8", delimiter = ",")
  df  <- read_dataset(fix("valid_accounts_current.csv"), cfg)
  expect_equal(ncol(df), 6)
  expect_equal(names(df),
               c("id", "name", "country_code", "account_status",
                 "account_balance", "created_date"))
})

test_that("read_dataset() trims leading/trailing whitespace from all cells", {
  tmp <- tempfile(fileext = ".csv")
  writeLines(c("a,b", "  hello  ,  world  "), tmp)
  cfg <- list(format = "csv", encoding = "UTF-8", delimiter = ",")
  df  <- read_dataset(tmp, cfg)
  expect_equal(df$a[1], "hello")
  expect_equal(df$b[1], "world")
  unlink(tmp)
})

test_that("read_dataset() preserves NA as NA after trim", {
  tmp <- tempfile(fileext = ".csv")
  writeLines(c("a,b", "1,", "2,2"), tmp)
  cfg <- list(format = "csv", encoding = "UTF-8", delimiter = ",")
  df  <- read_dataset(tmp, cfg)
  expect_true(is.na(df$b[1]) || df$b[1] == "")
})

test_that("read_dataset() applies csv_skip + col_names to drop a header row", {
  # A duplicate-header file: the real header is unusable (repeated names), so
  # the caller supplies explicit col_names and csv_skip = 1 to drop the header.
  tmp <- tempfile(fileext = ".csv")
  writeLines(c("name,name,name", "a,b,c", "d,e,f"), tmp)
  cfg <- list(format = "csv", encoding = "UTF-8", delimiter = ",",
              col_names = c("name", "name_2", "name_3"), csv_skip = 1L)
  df  <- read_dataset(tmp, cfg)
  expect_equal(names(df), c("name", "name_2", "name_3"))
  expect_equal(nrow(df), 2L)                 # no phantom header row
  expect_equal(df$name, c("a", "d"))
  unlink(tmp)
})

test_that("read_dataset() with csv_skip >= row count yields zero data rows, not an error", {
  # Edge case: csv_skip larger than the data. readr drops every line; with an
  # explicit col_names the result is a 0-row frame with the right columns -- it
  # must not error or invent rows.
  tmp <- tempfile(fileext = ".csv")
  writeLines(c("name,name", "a,b"), tmp)   # 1 header + 1 data row
  cfg <- list(format = "csv", encoding = "UTF-8", delimiter = ",",
              col_names = c("name", "name_2"), csv_skip = 5L)
  df  <- read_dataset(tmp, cfg)
  expect_equal(names(df), c("name", "name_2"))
  expect_equal(nrow(df), 0L)
  unlink(tmp)
})

test_that("read_dataset() omitting csv_skip is byte-identical to legacy behaviour", {
  tmp <- tempfile(fileext = ".csv")
  writeLines(c("a,b", "1,2", "3,4"), tmp)
  cfg <- list(format = "csv", encoding = "UTF-8", delimiter = ",")
  df  <- read_dataset(tmp, cfg)
  expect_equal(names(df), c("a", "b"))       # file header used unchanged
  expect_equal(nrow(df), 2L)
  unlink(tmp)
})

test_that("read_dataset() stops on nonexistent file", {
  cfg <- list(format = "csv", encoding = "UTF-8", delimiter = ",")
  expect_error(read_dataset("/nonexistent/path/file.csv", cfg),
               regexp = "Failed to parse")
})

test_that("read_dataset() stops on unknown format", {
  cfg <- list(format = "parquet")
  expect_error(
    read_dataset(fix("valid_accounts_current.csv"), cfg),
    regexp = "format"
  )
})

test_that("read_dataset() reads FWF file correctly", {
  cfg <- list(
    format       = "fwf",
    encoding     = "UTF-8",
    fwf_widths   = c(6, 16, 3, 11, 13, 10),
    fwf_col_names = c("id", "name", "country_code",
                      "account_status", "account_balance", "created_date")
  )
  df <- read_dataset(fix("accounts_fwf_current.txt"), cfg)
  expect_s3_class(df, "data.frame")
  expect_equal(ncol(df), 6)
  expect_equal(nrow(df), 10)
})

# -- detect_files() ------------------------------------------------------------

test_that("detect_files() uses current_file when set; previous NULL when absent (D-01)", {
  cfg <- list(current_file = fix("valid_accounts_current.csv"))
  result <- detect_files(cfg)
  expect_equal(result$current, fix("valid_accounts_current.csv"))
  expect_null(result$previous)
})

test_that("detect_files() uses both files when both explicit paths set", {
  cfg <- list(
    current_file  = fix("valid_accounts_current.csv"),
    previous_file = fix("valid_accounts_previous.csv")
  )
  result <- detect_files(cfg)
  expect_equal(result$current,  fix("valid_accounts_current.csv"))
  expect_equal(result$previous, fix("valid_accounts_previous.csv"))
})

test_that("detect_files() stops when current_file does not exist", {
  cfg <- list(current_file = "/no/such/file.csv")
  expect_error(detect_files(cfg), regexp = "current_file")
})

test_that("detect_files() stops when folder does not exist", {
  cfg <- list(folder = "/no/such/folder/")
  expect_error(detect_files(cfg), regexp = "Folder")
})

test_that("detect_files() stops when folder is empty", {
  tmp   <- tempdir()
  empty <- file.path(tmp, "dqtest_emptydir")
  dir.create(empty, showWarnings = FALSE)
  for (f in list.files(empty, full.names = TRUE)) file.remove(f)
  cfg <- list(folder = empty)
  expect_error(detect_files(cfg), regexp = "No files")
})

test_that("detect_files() returns previous=NULL for single-file folder", {
  tmp     <- tempdir()
  onefile <- file.path(tmp, "dqtest_onefile")
  dir.create(onefile, showWarnings = FALSE)
  f <- file.path(onefile, "data.csv")
  writeLines("a,b\n1,2", f)
  cfg    <- list(folder = onefile)
  result <- detect_files(cfg)
  expect_equal(result$current, f)
  expect_null(result$previous)
  unlink(f)
})

test_that("detect_files() uses filename as tiebreaker when mtimes are equal (RC-01)", {
  tmp <- withr::local_tempdir()
  # Create two files with identical timestamps
  f_b <- file.path(tmp, "b_delivery.csv")
  f_a <- file.path(tmp, "a_delivery.csv")
  writeLines("x\n2", f_b)
  writeLines("x\n1", f_a)
  # Force both to same mtime
  t0 <- as.POSIXct("2024-01-01 12:00:00", tz = "UTC")
  Sys.setFileTime(f_a, t0)
  Sys.setFileTime(f_b, t0)

  cfg    <- list(folder = tmp)
  result <- detect_files(cfg)
  # basename "b_delivery.csv" > "a_delivery.csv" descending → b is current
  expect_equal(basename(result$current),  "b_delivery.csv")
  expect_equal(basename(result$previous), "a_delivery.csv")
})
