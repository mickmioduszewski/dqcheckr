
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

# -- B-17: multi-byte / unknown declared encodings are not falsely PASSed -------

test_that(".encoding_class() separates UTF-8, single-byte, and other", {
  expect_equal(.encoding_class("UTF-8"),        "utf8")
  expect_equal(.encoding_class("utf8"),         "utf8")
  expect_equal(.encoding_class("ISO-8859-1"),   "single_byte")
  expect_equal(.encoding_class("iso8859-15"),   "single_byte")
  expect_equal(.encoding_class("latin1"),       "single_byte")
  expect_equal(.encoding_class("windows-1252"), "single_byte")
  expect_equal(.encoding_class("CP1250"),       "single_byte")
  expect_equal(.encoding_class("UTF-16LE"),     "other")
  expect_equal(.encoding_class("UTF-32"),       "other")
  expect_equal(.encoding_class("Shift-JIS"),    "other")
  expect_equal(.encoding_class("GB18030"),      "other")
})

test_that("a declared single-byte encoding is not scanned and PASSes QC-16", {
  lat <- write_latin1_csv(tempfile(fileext = ".csv"))
  on.exit(unlink(lat))
  cfg <- list(format = "csv", encoding = "ISO-8859-1", delimiter = ",")
  df  <- read_dataset(lat, cfg)
  expect_equal(attr(df, "dq_encoding")$enc_class, "single_byte")
  res <- check_file_encoding(df, cfg)
  expect_equal(res[[1]]$status, "PASS")
  expect_match(res[[1]]$observed, "by construction")
})

test_that("QC-16 WARNs (not PASS) for a multi-byte declared encoding (B-17)", {
  # UTF-16LE is multi-byte; dqcheckr scans only UTF-8, so it must not be
  # reported as 'single-byte, valid by construction'. It is read as declared and
  # flagged unverified.
  ascii <- write_ascii_csv(tempfile(fileext = ".csv"))
  on.exit(unlink(ascii))
  cfg <- list(format = "csv", encoding = "UTF-16LE", delimiter = ",")
  df  <- suppressWarnings(read_dataset(ascii, cfg))

  info <- attr(df, "dq_encoding")
  expect_equal(info$enc_class, "other")
  expect_false(info$scanned)               # the whole scan block was skipped

  res <- check_file_encoding(df, cfg)
  expect_length(res, 1)
  expect_equal(res[[1]]$status, "WARN")
  expect_no_match(res[[1]]$observed, "by construction")
  expect_match(res[[1]]$observed, "multi-byte")
})

# -- B-18: the UTF-8 scan streams in chunks (flat memory, correct boundaries) ---

test_that("scan_file_encoding() validates UTF-8 across chunk boundaries", {
  # 'A €B €C' -- the euro sign (E2 82 AC) is split by tiny chunk sizes, so a
  # correct scanner must carry the incomplete tail across the boundary.
  euro <- as.raw(c(0x41, 0xE2, 0x82, 0xAC, 0x42, 0xE2, 0x82, 0xAC, 0x43))
  f <- tempfile(); writeBin(euro, f); on.exit(unlink(f))
  for (cs in c(1L, 2L, 3L, 4L, 5L)) {
    expect_true(scan_file_encoding(f, chunk_size = cs)$valid,
                info = sprintf("chunk_size = %d", cs))
  }
})

test_that("scan_file_encoding() detects invalid bytes when chunked", {
  bad <- as.raw(c(0x41, 0x82, 0x42, 0x43))      # lone continuation byte
  f <- tempfile(); writeBin(bad, f); on.exit(unlink(f))
  expect_false(scan_file_encoding(f, chunk_size = 2L)$valid)
})

test_that("scan_file_encoding() flags a multi-byte sequence truncated at EOF", {
  trunc <- as.raw(c(0x41, 0x42, 0xE2))          # 3-byte lead with no continuation
  f <- tempfile(); writeBin(trunc, f); on.exit(unlink(f))
  expect_false(scan_file_encoding(f, chunk_size = 2L)$valid)
})

test_that(".utf8_incomplete_tail() holds back only genuinely incomplete tails", {
  # Complete ASCII / complete sequence -> nothing held.
  expect_equal(.utf8_incomplete_tail(as.raw(c(0x41, 0x42))), 0L)
  expect_equal(.utf8_incomplete_tail(as.raw(c(0xE2, 0x82, 0xAC))), 0L)
  # Lone 3-byte lead -> hold 1; lead + one continuation of a 3-byte -> hold 2.
  expect_equal(.utf8_incomplete_tail(as.raw(c(0x41, 0xE2))), 1L)
  expect_equal(.utf8_incomplete_tail(as.raw(c(0x41, 0xE2, 0x82))), 2L)
  # Lone 2-byte lead -> hold 1.
  expect_equal(.utf8_incomplete_tail(as.raw(c(0x41, 0xC3))), 1L)
})
