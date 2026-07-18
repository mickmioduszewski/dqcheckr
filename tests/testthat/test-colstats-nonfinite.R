# Non-finite parses and zero-column deliveries in the column-stat path.
#
# B-23: an upstream delivery containing Inf/-Inf (write.csv emits the literal
# text "Inf"/"-Inf"; as.numeric() parses them back to infinities) makes the
# numeric aggregates degrade to NaN -- compute_col_stats() would store the
# literal string "NaN"/"Inf" and poison drift arithmetic, while check_outliers()
# aborts untyped when sd() returns NaN and `if (sdev > 0)` sees a missing value.
# Both now drop non-finite parses before aggregating.
#
# B-11: a zero-column delivery (empty file) produces no per-column frames, so
# do.call(rbind, list()) was NULL and the whole snapshot row was lost. The run
# must still be recorded.

cfg_stats <- function(extra = list()) {
  utils::modifyList(
    list(format = "csv", delimiter = ",",
         rules = list(max_missing_rate = 0.05, max_non_numeric_rate = 0.01,
                      type_inference_threshold = 0.90),
         column_rules = list(), column_types = list()),
    extra)
}

# -- B-23: compute_col_stats never stores a non-finite value ----------------------

test_that("compute_col_stats() never stores non-finite values in the snapshot DB", {
  df  <- data.frame(amt = c("Inf", "-Inf", "5"), stringsAsFactors = FALSE)
  cfg <- cfg_stats()

  # Precondition: "Inf" parses as numeric, so the column resolves to numeric
  # and the numeric stat branch runs.
  expect_equal(resolve_col_type("amt", df$amt, cfg), "numeric")

  cs <- compute_col_stats(df, cfg)
  stats <- cs[cs$dq_check %in% c("numeric_parseable_mean", "numeric_sd",
                                 "numeric_min", "numeric_max"), ]

  parsed <- suppressWarnings(as.numeric(stats$value))
  expect_true(all(is.na(stats$value) | is.finite(parsed)),
              info = paste(stats$dq_check, stats$value, collapse = "; "))
})

test_that("mean drift away from an Inf-contaminated column is still reported", {
  cfg <- cfg_stats()
  mk  <- function(lines) { f <- tempfile(fileext = ".csv"); writeLines(lines, f); f }
  db  <- tempfile(fileext = ".sqlite")

  f1 <- mk(c("amt", "100", "100", "100"))
  d1 <- read_dataset(f1, cfg)
  write_snapshot(db, "probe", basename(f1), d1, list(), list(), list(), cfg)

  # Upstream contaminated the column with infinities: the finite mean is 5, a
  # large shift from 100 -- it must not be silently dropped from the drift table.
  f2 <- mk(c("amt", "Inf", "-Inf", "5"))
  d2 <- read_dataset(f2, cfg)
  write_snapshot(db, "probe", basename(f2), d2, list(), list(), list(), cfg)

  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  drift <- dqcheckr:::.compute_drift(con, "probe", 1, 2, list(
    max_missing_rate_change_pp = 2.0, max_non_numeric_rate_change_pp = 1.0,
    max_numeric_mean_shift_pct = 0.20, max_row_count_change_pct = 0.10))

  expect_gt(nrow(drift$mean_shifts), 0)
})

# -- B-23: check_outliers does not abort on an Inf-contaminated column -------------

test_that("check_outliers() does not abort when a numeric column contains Inf", {
  df  <- data.frame(amt = c("Inf", "1", "2", "3", "4", "100"),
                    stringsAsFactors = FALSE)
  cfg <- cfg_stats(list(rules = list(max_missing_rate = 0.05,
                                     max_non_numeric_rate = 0.01,
                                     type_inference_threshold = 0.90,
                                     max_z_score = 3)))
  expect_equal(resolve_col_type("amt", df$amt, cfg), "numeric")

  res <- check_outliers(df, cfg)                 # aborted pre-fix: `if (NaN > 0)`
  expect_length(res, 1)
  expect_true(res[[1]]$status %in% c("PASS", "FAIL"))
})

# -- B-11: a zero-column delivery still records a snapshot -------------------------

test_that("compute_col_stats() returns a typed empty frame for a zero-column frame", {
  cs <- compute_col_stats(data.frame(), cfg_stats())
  expect_s3_class(cs, "data.frame")
  expect_equal(nrow(cs), 0L)
  expect_named(cs, c("column_name", "dq_check", "value",
                     "threshold", "severity_on_breach"))
})

test_that("write_snapshot() records a snapshot for a zero-column delivery", {
  db  <- tempfile(fileext = ".sqlite")
  sid <- write_snapshot(db, "empty", "empty.csv", data.frame(),
                        list(), list(), list(), cfg_stats())
  expect_false(is.null(sid))

  h <- read_recent_snapshots(db, "empty", n = 1)
  expect_equal(nrow(h), 1L)
  expect_equal(h$col_count[1], 0L)
})
