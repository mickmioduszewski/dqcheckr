
# Byte-exact fixture writers: writeLines() would re-encode via the native
# locale, so the files are written as raw bytes instead.
write_utf8_csv <- function(path) {
  txt <- "name,city\nZoë,München\nMick,Sydney\n"
  writeBin(charToRaw(enc2utf8(txt)), path)
  path
}
write_latin1_csv <- function(path) {
  txt <- "name,city\nZoë,München\nMick,Sydney\n"
  writeBin(charToRaw(iconv(txt, from = "UTF-8", to = "ISO-8859-1")), path)
  path
}
write_ascii_csv <- function(path) {
  writeBin(charToRaw("name,city\nMick,Sydney\n"), path)
  path
}

# -- normalise_encoding() ------------------------------------------------------

test_that("normalise_encoding() maps ASCII aliases to UTF-8, case-insensitively", {
  expect_equal(normalise_encoding("ASCII"), "UTF-8")
  expect_equal(normalise_encoding("ascii"), "UTF-8")
  expect_equal(normalise_encoding(" US-ASCII "), "UTF-8")
  expect_equal(normalise_encoding("ANSI_X3.4-1968"), "UTF-8")
})

test_that("normalise_encoding() leaves real encodings untouched", {
  expect_equal(normalise_encoding("UTF-8"), "UTF-8")
  expect_equal(normalise_encoding("ISO-8859-1"), "ISO-8859-1")
  expect_equal(normalise_encoding("windows-1252"), "windows-1252")
  expect_equal(normalise_encoding("UTF-16LE"), "UTF-16LE")
})

# -- scan_file_encoding() ------------------------------------------------------

test_that("scan_file_encoding() accepts valid UTF-8 and pure ASCII", {
  utf8  <- write_utf8_csv(tempfile(fileext = ".csv"))
  ascii <- write_ascii_csv(tempfile(fileext = ".csv"))
  expect_true(scan_file_encoding(utf8)$valid)
  expect_true(scan_file_encoding(ascii)$valid)
  unlink(c(utf8, ascii))
})

test_that("scan_file_encoding() rejects latin1 bytes and offers a guess", {
  lat <- write_latin1_csv(tempfile(fileext = ".csv"))
  scan <- scan_file_encoding(lat)
  expect_false(scan$valid)
  # The guess is statistical; it must at least not claim a Unicode encoding.
  if (!is.null(scan$guess)) expect_false(grepl("^UTF", scan$guess))
  unlink(lat)
})

test_that("scan_file_encoding() finds non-ASCII bytes beyond a head sample", {
  # The failure mode that motivated the scan: a large ASCII prefix with the
  # first accented byte deep in the file.
  tmp <- tempfile(fileext = ".csv")
  con <- file(tmp, open = "wb")
  writeBin(charToRaw("name,city\n"), con)
  filler <- charToRaw(paste0(strrep("Mick,Sydney\n", 1000)))
  for (i in 1:200) writeBin(filler, con)  # ~2.4 MB of pure ASCII rows
  writeBin(charToRaw(iconv("Zoë,München\n", "UTF-8", "ISO-8859-1")), con)
  close(con)
  expect_false(scan_file_encoding(tmp)$valid)
  unlink(tmp)
})

test_that("scan_file_encoding() treats an empty file as valid", {
  tmp <- tempfile(fileext = ".csv")
  file.create(tmp)
  expect_true(scan_file_encoding(tmp)$valid)
  unlink(tmp)
})

# -- read_dataset() encoding behaviour -----------------------------------------

test_that("declared ASCII reads a UTF-8 file with non-ASCII bytes (no crash)", {
  utf8 <- write_utf8_csv(tempfile(fileext = ".csv"))
  cfg  <- list(format = "csv", encoding = "ASCII", delimiter = ",")
  df   <- read_dataset(utf8, cfg)
  expect_equal(df$name[1], "Zoë")
  info <- attr(df, "dq_encoding")
  expect_equal(info$declared, "ASCII")
  expect_equal(info$used, "UTF-8")
  expect_true(info$valid)
  expect_true(info$scanned)
  unlink(utf8)
})

test_that("a latin1 delivery declared UTF-8 is read via fallback, not crashed", {
  lat <- write_latin1_csv(tempfile(fileext = ".csv"))
  cfg <- list(format = "csv", delimiter = ",")  # encoding defaults to UTF-8
  df  <- read_dataset(lat, cfg)
  expect_equal(df$name[1], "Zoë")  # fallback single-byte read is correct
  info <- attr(df, "dq_encoding")
  expect_false(info$valid)
  expect_true(info$scanned)
  expect_true(grepl("^(ISO-8859|windows-125)", info$used, ignore.case = TRUE))
  unlink(lat)
})

test_that("a declared single-byte encoding skips the scan", {
  lat <- write_latin1_csv(tempfile(fileext = ".csv"))
  cfg <- list(format = "csv", encoding = "ISO-8859-1", delimiter = ",")
  df  <- read_dataset(lat, cfg)
  expect_equal(df$name[1], "Zoë")
  info <- attr(df, "dq_encoding")
  expect_true(info$valid)
  expect_false(info$scanned)
  unlink(lat)
})

# -- check_file_encoding() (QC-16) ---------------------------------------------

test_that("QC-16 passes for a valid UTF-8 delivery", {
  utf8 <- write_utf8_csv(tempfile(fileext = ".csv"))
  cfg  <- list(format = "csv", encoding = "UTF-8", delimiter = ",")
  df   <- read_dataset(utf8, cfg)
  res  <- check_file_encoding(df, cfg)
  expect_length(res, 1)
  expect_equal(res[[1]]$check_id, "QC-16")
  expect_equal(res[[1]]$status, "PASS")
  unlink(utf8)
})

test_that("QC-16 fails for a latin1 delivery declared UTF-8", {
  lat <- write_latin1_csv(tempfile(fileext = ".csv"))
  cfg <- list(format = "csv", encoding = "UTF-8", delimiter = ",")
  df  <- read_dataset(lat, cfg)
  res <- check_file_encoding(df, cfg)
  expect_length(res, 1)
  expect_equal(res[[1]]$status, "FAIL")
  expect_match(res[[1]]$message, "not valid UTF-8")
  unlink(lat)
})

test_that("QC-16 is silent for a data frame not from read_dataset()", {
  df  <- data.frame(a = c("1", "2"), stringsAsFactors = FALSE)
  cfg <- list(format = "csv")
  expect_length(check_file_encoding(df, cfg), 0)
})

test_that("QC-16 WARNs (not PASS) when the UTF-8 scan itself fails (B-15)", {
  # A scan error (e.g. OOM on a huge file) must not become a confident PASS with
  # a bogus "valid by construction" rationale. read_dataset() records the scan
  # failure and reads the file as declared; QC-16 reports it as unverified.
  utf8 <- write_utf8_csv(tempfile(fileext = ".csv"))
  on.exit(unlink(utf8))
  cfg  <- list(format = "csv", encoding = "UTF-8", delimiter = ",")

  testthat::local_mocked_bindings(
    scan_file_encoding = function(...) stop("simulated scan failure (out of memory)"))
  df  <- read_dataset(utf8, cfg)          # must still read, not abort
  expect_s3_class(df, "data.frame")

  res <- check_file_encoding(df, cfg)
  expect_length(res, 1)
  expect_equal(res[[1]]$status, "WARN")
  expect_match(res[[1]]$observed, "Could not verify")
  expect_match(res[[1]]$observed, "out of memory")
  # It must NOT reuse the single-byte "valid by construction" wording.
  expect_no_match(res[[1]]$observed, "by construction")
})

test_that("run_qc_checks() includes exactly one QC-16 result for a read df", {
  utf8 <- write_utf8_csv(tempfile(fileext = ".csv"))
  cfg  <- list(format = "csv", encoding = "UTF-8", delimiter = ",")
  df   <- read_dataset(utf8, cfg)
  ids  <- vapply(run_qc_checks(df, cfg), function(r) r$check_id, character(1))
  expect_equal(sum(ids == "QC-16"), 1)
  unlink(utf8)
})
