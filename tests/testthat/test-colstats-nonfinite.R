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

# -- B-01: the invariant holds for aggregate OVERFLOW, not just non-finite inputs -

test_that("compute_col_stats() stores no non-finite literal for any column (property, B-01)", {
  cfg <- cfg_stats()
  # Each column is numeric-resolvable and stresses a different non-finite path.
  cases <- list(
    inf_inputs       = c("Inf", "-Inf", "5"),          # B-23 input path
    sd_overflow      = c("1e300", "1.5e300", "2e300"),  # sd() squares past double max
    two_val_overflow = c("1e300", "2e300"),             # sd overflow with n = 2
    huge_identical   = c("1e308", "1e308", "1e308"),    # internal overflow, true sd is 0
    normal           = c("1", "2", "3", "4")
  )
  stat_checks <- c("numeric_parseable_mean", "numeric_sd",
                   "numeric_min", "numeric_max")
  for (nm in names(cases)) {
    df <- data.frame(amt = cases[[nm]], stringsAsFactors = FALSE)
    expect_equal(resolve_col_type("amt", df$amt, cfg), "numeric", info = nm)
    stats <- compute_col_stats(df, cfg)
    s <- stats[stats$dq_check %in% stat_checks, ]
    parsed <- suppressWarnings(as.numeric(s$value))
    # Every stored numeric aggregate is NA or a finite number -- never the
    # literal "Inf"/"-Inf"/"NaN" that would poison drift arithmetic.
    expect_true(all(is.na(s$value) | is.finite(parsed)),
                info = paste0(nm, ": ", paste(s$dq_check, s$value, collapse = "; ")))
  }
})

test_that("compute_col_stats() keeps finite min/max but NAs an overflowing sd (B-01)", {
  cfg <- cfg_stats()
  stats <- compute_col_stats(
    data.frame(amt = c("1e300", "1.5e300", "2e300"), stringsAsFactors = FALSE), cfg)
  val <- function(chk) stats$value[stats$dq_check == chk]
  # min/max select existing finite values -- they never overflow, so they persist.
  expect_equal(val("numeric_min"), "1e+300")
  expect_equal(val("numeric_max"), "2e+300")
  # sd overflows the double range -> stored NA, not the literal "Inf".
  expect_true(is.na(val("numeric_sd")))
})

# -- B-01 read side: a legacy DB already carrying "Inf" must not re-poison drift --

test_that(".safe_num() maps every non-finite parse to NA (B-01 read side)", {
  expect_equal(dqcheckr:::.safe_num(c("Inf", "5", "NaN", "-Inf", NA, "2.5")),
               c(NA, 5, NA, NA, NA, 2.5))
})

test_that(".compute_drift() treats a pre-fix stored 'Inf' mean as missing, not Inf (B-01)", {
  db  <- make_drift_db(2)                       # finite means 100 (id1) -> 200 (id2)
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  # Simulate a snapshot written by a pre-0.2.5 dqcheckr before the write guard.
  DBI::dbExecute(con,
    "UPDATE column_snapshots SET value = 'Inf'
     WHERE snapshot_id = 2 AND dq_check = 'numeric_parseable_mean'
       AND column_name = 'amount'")

  drift <- dqcheckr:::.compute_drift(con, "test_ds", 1, 2, list(
    max_missing_rate_change_pp = 2.0, max_non_numeric_rate_change_pp = 1.0,
    max_numeric_mean_shift_pct = 0.20, max_row_count_change_pct = 0.10))

  # The poisoned column drops out of the mean-shift table cleanly (treated as
  # missing) rather than producing an Inf/NaN row -- no non-finite leaks through.
  ms <- drift$mean_shifts
  expect_false(any(is.infinite(ms$numeric_mean_shift_pct)))
  expect_false(any(is.nan(ms$numeric_mean_shift_pct)))
  expect_false("amount" %in% ms$Column)
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
