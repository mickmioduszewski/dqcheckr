# sniff_dataset(): pure inference (plan step 6). Field-by-field expect_equal
# on the returned list -- the design's stated test style for this function.

sniff_file <- function(lines, ext = ".csv") {
  f <- tempfile(fileext = ext)
  writeLines(lines, f)
  f
}

# -- delimiters ----------------------------------------------------------------

test_that("comma, semicolon, tab, and pipe delimiters are each detected", {
  for (d in c(",", ";", "\t", "|")) {
    f <- sniff_file(c(paste("id", "amount", sep = d),
                      paste("A1", "10",     sep = d),
                      paste("A2", "20",     sep = d)))
    on.exit(unlink(f), add = TRUE)
    s <- sniff_dataset(f)
    expect_equal(s$format, "csv")
    expect_equal(s$delimiter, d)
    expect_equal(s$provenance[["delimiter"]], "detected")
    expect_equal(s$col_names, c("id", "amount"))
  }
})

test_that("quoted fields containing the delimiter do not skew detection", {
  f <- sniff_file(c('name,notes', '"Smith, John","a, b, c"', '"Lee, Ann","d"'))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$delimiter, ",")
  expect_equal(s$quote_char, '"')
  expect_equal(s$col_names, c("name", "notes"))
  expect_equal(s$n_sample_rows, 2L)
})

test_that("a single-quote-quoted file falls back to the second quote candidate", {
  f <- sniff_file(c("id;note", "'x;1';'a;b'", "'y;2';'c'"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$delimiter, ";")
  expect_equal(s$quote_char, "'")
  expect_equal(s$provenance[["quote_char"]], "detected")
  expect_equal(s$col_names, c("id", "note"))
})

test_that("a single-column file sniffs as csv with default delimiter/quote", {
  f <- sniff_file(c("id", "A1", "A2", "A300"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$format, "csv")
  expect_equal(s$delimiter, .default_read$delimiter)
  expect_equal(s$quote_char, .default_read$quote_char)
  expect_equal(s$provenance[["delimiter"]], "default")
  expect_equal(s$col_names, "id")
  expect_equal(s$header, TRUE)
  expect_equal(s$n_sample_rows, 3L)
})

# -- header detection ----------------------------------------------------------

test_that("a string first row over numeric data detects a header", {
  f <- sniff_file(c("id,amount", "1,10", "2,20"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$header, TRUE)
  expect_equal(s$provenance[["header"]], "detected")
  expect_equal(s$col_names, c("id", "amount"))
  expect_equal(s$csv_skip, 0L)
})

test_that("a numeric-looking first row means no header, with generated names", {
  f <- sniff_file(c("1,10", "2,20", "3,30"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$header, FALSE)
  expect_equal(s$col_names, c("col_1", "col_2"))
  expect_equal(s$provenance[["col_names"]], "generated")
  expect_equal(s$n_sample_rows, 3L)          # first row is data
})

test_that("an all-text file is assumed headed", {
  f <- sniff_file(c("name,city", "alice,london", "bob,paris"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$header, TRUE)
  expect_equal(s$col_names, c("name", "city"))
})

# -- duplicate header names ----------------------------------------------------

test_that("duplicate header names get positional renames, originals recorded, csv_skip 1", {
  f <- sniff_file(c("Date,Amount,Currency,Amount,Status",
                    "2026-07-01,100.00,AUD,15.00,settled"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$col_names, c("Date", "Amount", "Currency", "Amount_2", "Status"))
  expect_equal(s$renamed_from, c(Amount_2 = "Amount"))
  expect_equal(s$csv_skip, 1L)               # col_names will replace the header
})

test_that("triple duplicates number 2 and 3; unique headers rename nothing", {
  f <- sniff_file(c("x,x,x", "1,2,3"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$col_names, c("x", "x_2", "x_3"))
  expect_equal(s$renamed_from, c(x_2 = "x", x_3 = "x"))

  g <- sniff_file(c("a,b,c", "1,2,3"))
  on.exit(unlink(g), add = TRUE)
  s2 <- sniff_dataset(g)
  expect_null(s2$renamed_from)
  expect_equal(s2$csv_skip, 0L)
})

# -- encoding ------------------------------------------------------------------

test_that("clean UTF-8 sniffs as UTF-8, valid, no guess, no BOM", {
  f <- sniff_file(c("name,city", "Café,Zürich"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$encoding, "UTF-8")
  expect_true(s$encoding_valid_utf8)
  expect_null(s$encoding_guess)
  expect_false(s$bom)
})

test_that("a UTF-8 BOM is flagged and does not corrupt the first column name", {
  f <- tempfile(fileext = ".csv")
  writeBin(c(charToRaw("\xEF\xBB\xBF"), charToRaw("id,amount\nA1,10\n")), f)
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_true(s$bom)
  expect_equal(s$col_names, c("id", "amount"))
})

test_that("invalid UTF-8 records the fallback encoding and the guess, like QC-16", {
  f <- tempfile(fileext = ".csv")
  writeBin(charToRaw("name,city\nCaf\xe9,Par\xees\n"), f)   # latin-1 bytes
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_false(s$encoding_valid_utf8)
  # Same fallback rule as read_dataset: the guess if single-byte, else ISO-8859-1.
  expect_equal(s$encoding, .safe_fallback_encoding(s$encoding_guess))
  expect_match(s$encoding, "^(ISO-8859|windows-125)", ignore.case = TRUE)
  expect_equal(s$col_names, c("name", "city"))   # header still parsed
})

# -- graceful edges ------------------------------------------------------------

test_that("a missing file aborts with dqcheckr_missing_file", {
  expect_error(sniff_dataset(tempfile()), class = "dqcheckr_missing_file")
})

test_that("an empty file aborts with dqcheckr_empty_file", {
  f <- sniff_file(character(0))
  on.exit(unlink(f))
  expect_error(sniff_dataset(f), class = "dqcheckr_empty_file")
  g <- sniff_file(c("", "  "))
  on.exit(unlink(g), add = TRUE)
  expect_error(sniff_dataset(g), class = "dqcheckr_empty_file")
})

test_that("a header-only file returns gracefully with zero sample rows and no types", {
  f <- sniff_file("id,amount,status")
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$header, TRUE)
  expect_equal(s$provenance[["header"]], "default")   # nothing to compare against
  expect_equal(s$col_names, c("id", "amount", "status"))
  expect_equal(s$n_sample_rows, 0L)
  expect_equal(s$column_types, character(0))
  expect_equal(s$key_column_candidates, character(0))
})

# -- type inference parity -----------------------------------------------------

test_that("sniffed types agree with infer_col_type() on the same values by construction", {
  f <- sniff_file(c("id,when,amt,label",
                    "202401159,2026-01-15,10.5,x",
                    "202401160,2026-02-20,11.0,y",
                    "202401161,2026-03-25,12.5,z"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(unname(s$column_types),
               c(infer_col_type(c("202401159", "202401160", "202401161")),
                 infer_col_type(c("2026-01-15", "2026-02-20", "2026-03-25")),
                 infer_col_type(c("10.5", "11.0", "12.5")),
                 infer_col_type(c("x", "y", "z"))))
  # The 9-digit id must NOT classify as a date (the anchored shape guard).
  expect_equal(unname(s$column_types[["id"]]), "numeric")
  expect_equal(unname(s$column_types[["when"]]), "date")
})

test_that("key-column candidates are the unique, fully-present sampled columns", {
  f <- sniff_file(c("id,status,ref",
                    "A1,open,",
                    "A2,open,r2",
                    "A3,closed,r3"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  # id: unique+present -> candidate. status: duplicated -> no. ref: missing -> no.
  expect_equal(s$key_column_candidates, "id")
  expect_equal(s$expected_columns, c("id", "status", "ref"))
})

# -- FWF -----------------------------------------------------------------------

test_that("a gutter-separated FWF file gets widths from fwf_empty, contiguous cover", {
  f <- sniff_file(c("A1  100  open ",
                    "B2  200  shut ",
                    "C3  300  open "), ext = ".txt")
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$format, "fwf")
  expect_equal(sum(s$fwf_widths), nchar("A1  100  open "))  # covers the record
  expect_equal(length(s$fwf_widths), 3L)
  expect_equal(s$fwf_col_names, c("col_1", "col_2", "col_3"))
  expect_false(s$fwf_packed)
  expect_equal(s$n_sample_rows, 3L)
  # Types inferred from the extracted, trimmed column samples.
  expect_equal(unname(s$column_types), c("character", "numeric", "character"))
  # col_1 and col_2 are both unique and fully present in the sample; col_3
  # repeats "open" so it is rightly excluded.
  expect_equal(s$key_column_candidates, c("col_1", "col_2"))
})

test_that("a packed FWF file sets the packed marker and never a confident wrong guess", {
  f <- sniff_file(c("AB12XY", "CD34ZW", "EF56QQ"), ext = ".txt")
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_equal(s$format, "fwf")
  expect_true(s$fwf_packed)
  expect_null(s$fwf_widths)
  expect_null(s$fwf_col_names)
})

test_that("varied-length lines without a delimiter stay csv, not fwf", {
  f <- sniff_file(c("id", "A1", "A2000", "B3"))
  on.exit(unlink(f))
  expect_equal(sniff_dataset(f)$format, "csv")
})

# -- purity and provenance -----------------------------------------------------

test_that("sniffing is pure: the file is byte-identical afterwards and nothing else is created", {
  f <- sniff_file(c("id,amount", "A1,10"))
  on.exit(unlink(f))
  before_bytes <- readBin(f, "raw", file.size(f))
  dir_before   <- list.files(dirname(f))
  invisible(sniff_dataset(f))
  expect_identical(readBin(f, "raw", file.size(f)), before_bytes)
  expect_identical(list.files(dirname(f)), dir_before)
})

test_that("provenance is complete and uses only the three allowed origins", {
  f <- sniff_file(c("id,amount", "A1,10"))
  on.exit(unlink(f))
  s <- sniff_dataset(f)
  expect_named(s$provenance, c("format", "encoding", "delimiter", "quote_char",
                               "header", "col_names"))
  expect_true(all(s$provenance %in% c("detected", "default", "generated")))
})

test_that("the full inference list has exactly the documented fields", {
  f <- sniff_file(c("id,amount", "A1,10"))
  on.exit(unlink(f))
  expect_named(sniff_dataset(f),
               c("path", "format", "encoding", "encoding_valid_utf8",
                 "encoding_guess", "bom", "delimiter", "quote_char", "header",
                 "csv_skip", "col_names", "renamed_from", "fwf_widths",
                 "fwf_col_names", "fwf_packed", "column_types",
                 "key_column_candidates", "expected_columns", "n_sample_rows",
                 "provenance"))
})
