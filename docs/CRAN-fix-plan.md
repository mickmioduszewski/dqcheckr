# CRAN Fix Plan — dqcheckr 0.2.0

**Based on**: CRAN-diagnosis.md\
**Date**: 2026-05-31\
**Target**: eliminate all 4 CRAN ERRORs on Debian and harden against
regression

------------------------------------------------------------------------

## Execution order

Apply fixes in the order below. Each fix is self-contained and can be
verified independently. Complete all code fixes before adding tests (Fix
7), then update NEWS.md last.

| \# | Priority | File(s) | What changes |
|----|----|----|----|
| 1 | P1 Critical | `R/report.R` | Add `intermediates_dir` + pandoc guard to `render_report()` |
| 2 | P1 Critical | `R/run_check.R` | Handle `NULL` report_path when pandoc absent |
| 3 | P1 Critical | `R/drift.R` | Add `intermediates_dir` to `.write_drift_html_report()` |
| 4 | P3 Moderate | `inst/demonstrations/output2/` | Delete directory from package |
| 5 | P3 Moderate | `.Rbuildignore` | Add guard against output directories in `inst/demonstrations/` |
| 6 | P4 Moderate | `tests/testthat/test-integration.R` | Absolute paths in global config + pandoc skip guards |
| 7 | P5 Moderate | `R/drift.R` | Change [`list_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/list_snapshots.md) default `db_path` to `NULL` |
| 8 | P6 Low | `tests/testthat/test-integration.R`, new `tests/testthat/test-report-tempdir.R` | Add T-01 through T-05 |
| 9 | — | `NEWS.md` | Document bug fixes |

------------------------------------------------------------------------

## Fix 1 — `R/report.R`: add `intermediates_dir` and pandoc guard to `render_report()`

**Lines affected**: 1–48 (entire function)

Two changes to the same function:

**Change A — pandoc guard** (after the template existence check, before
`dir.create`):

``` r

# Add after line 9 (after the nzchar template check):
if (!rmarkdown::pandoc_available()) {
  warning("Pandoc not found. HTML report skipped.", call. = FALSE)
  return(invisible(NULL))
}
```

**Change B — `intermediates_dir` in
[`rmarkdown::render()`](https://pkgs.rstudio.com/rmarkdown/reference/render.html)**
(the root-cause fix):

``` r

# In the rmarkdown::render() call, add intermediates_dir:
rmarkdown::render(
  input             = template,
  output_file       = out,
  intermediates_dir = tempdir(),    # ADD: prevents writes to user library
  params            = list(
    dataset_name     = dataset_name,
    file_name        = file_name,
    file_path        = file_path,
    run_timestamp    = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    df               = df,
    qc_results       = qc_results,
    cp_results       = cp_results,
    custom_results   = custom_results,
    snapshot_history = snapshot_history,
    config           = config,
    col_stats        = col_stats,
    overall_status   = overall_status(c(qc_results, cp_results,
                                        custom_results))
  ),
  quiet = TRUE
)
```

**Verification**: after this fix,
`list.files(system.file("templates", package = "dqcheckr"))` must return
the same files before and after a `render_report()` call.

------------------------------------------------------------------------

## Fix 2 — `R/run_check.R`: handle `NULL` report_path when pandoc absent

**Lines affected**: 78–99 (the `render_report()` call and the
message/return block)

`render_report()` now returns `NULL` when pandoc is unavailable.
[`run_dq_check()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_dq_check.md)
must not crash on that `NULL` and must still return a useful result.

**Change**: update the
[`message()`](https://rdrr.io/r/base/message.html) call to handle `NULL`
report_path:

``` r

report_path <- render_report(
  dataset_name     = dataset_name,
  file_name        = basename(files$current),
  file_path        = files$current,
  df               = df_curr,
  qc_results       = qc_results,
  cp_results       = cp_results,
  custom_results   = custom_results,
  snapshot_history = snapshot_history,
  config           = config,
  col_stats        = col_stats,
  output_dir       = config$report_output_dir %||% "reports/",
  open_report      = open_report
)

status <- overall_status(c(qc_results, cp_results, custom_results))
all_r  <- c(qc_results, cp_results, custom_results)
n_warn <- sum(vapply(all_r, \(r) r$status == "WARN", logical(1)))
n_fail <- sum(vapply(all_r, \(r) r$status == "FAIL", logical(1)))

report_label <- if (!is.null(report_path)) report_path else "(pandoc not available)"
message(sprintf("[dqcheckr] %s: %s - %d warning(s), %d failure(s). Report: %s",
                dataset_name, status, n_warn, n_fail, report_label))

invisible(list(
  status      = status,
  report_path = report_path,   # NULL when pandoc absent — documented behaviour
  snapshot_id = snapshot_id
))
```

**Verification**: calling
[`run_dq_check()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_dq_check.md)
in an environment without pandoc must return
`list(status = ..., report_path = NULL, snapshot_id = <integer>)` with a
warning, not an error. The snapshot must be written to SQLite
regardless.

------------------------------------------------------------------------

## Fix 3 — `R/drift.R`: add `intermediates_dir` to `.write_drift_html_report()`

**Lines affected**: 464–469 (the
[`rmarkdown::render()`](https://pkgs.rstudio.com/rmarkdown/reference/render.html)
call inside `.write_drift_html_report()`)

The pandoc guard already exists in this function (lines 458–461). Only
the `intermediates_dir` argument is missing:

``` r

rmarkdown::render(
  input             = template,
  output_file       = tmp_out,
  intermediates_dir = tempdir(),    # ADD: prevents writes to user library
  params            = list(drift = drift),
  quiet             = TRUE
)
```

**Verification**: same as Fix 1 — template directory must be unchanged
after a `compare_snapshots(report = TRUE)` call.

------------------------------------------------------------------------

## Fix 4 — Delete `inst/demonstrations/output2/`

Remove the following from the package source tree entirely:

    inst/demonstrations/output2/reports/drift_RBB_bonds_20260531_144410.html
    inst/demonstrations/output2/reports/drift_RBB_bonds_20260531_153430.html
    inst/demonstrations/output2/reports/RBB_bonds_20260531_120808.html
    inst/demonstrations/output2/reports/RBB_bonds_20260531_142826.html
    inst/demonstrations/output2/reports/RBB_bonds_20260531_143221.html
    inst/demonstrations/output2/reports/RBB_bonds_20260531_143627.html
    inst/demonstrations/output2/reports/RBB_bonds_20260531_150434.html
    inst/demonstrations/output2/reports/starwars_folder_20260531_110203.html
    inst/demonstrations/output2/reports/starwars_folder_20260531_110204.html
    inst/demonstrations/output2/reports/starwars_folder_20260531_110351.html
    inst/demonstrations/output2/snapshots.sqlite

**Command**: `unlink("inst/demonstrations/output2", recursive = TRUE)`
or equivalent `git rm -r inst/demonstrations/output2`.

**Verification**: `dir.exists("inst/demonstrations/output2")` returns
`FALSE`. The demo scripts (`demo2.R`) and demo configs (`config2/`) are
not touched.

------------------------------------------------------------------------

## Fix 5 — `.Rbuildignore`: guard against future output directories in `inst/demonstrations/`

Add one line to `.Rbuildignore`:

    ^inst/demonstrations/output

This matches `output/`, `output2/`, or any future `outputN/` directory
under `inst/demonstrations/`, preventing re-inclusion if someone runs
the demos locally and accidentally stages the results.

Note: the existing `^.*\.sqlite$` line excludes SQLite files at the
package root but does NOT exclude them inside `inst/`. The new line
covers that gap for the demonstrations directory.

------------------------------------------------------------------------

## Fix 6 — `tests/testthat/test-integration.R`: absolute paths + pandoc skip guards

Two changes to the same file.

**Change A — absolute paths in `setup_integration_env()` global
config**:

Replace the relative-path global config with absolute tempdir paths:

``` r

# BEFORE:
writeLines(c(
  "snapshot_db: 'data/snapshots.sqlite'",
  "report_output_dir: 'reports/'",
  ...
), file.path(cfg, "dqcheckr.yml"))

# AFTER:
writeLines(c(
  sprintf("snapshot_db: '%s'",        file.path(cfg, "snapshots.sqlite")),
  sprintf("report_output_dir: '%s'",  file.path(cfg, "reports")),
  ...
), file.path(cfg, "dqcheckr.yml"))
```

**Change B — pandoc skip guard on the report-path test only**:

The test at line 53 specifically asserts that an HTML file was written.
This requires pandoc. Add a skip guard to that test alone; the other
three tests (status, snapshot_id, return type) do not require pandoc and
must remain unguarded:

``` r

test_that("run_dq_check() writes an HTML report file to disk", {
  skip_if_not(rmarkdown::pandoc_available())   # ADD
  cfg_dir <- setup_integration_env()
  result  <- run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  expect_true(file.exists(result$report_path))
  expect_match(result$report_path, "\\.html$")
})
```

The other three integration tests remain as-is; they test status,
snapshot_id, and return structure — all of which work without pandoc
after Fix 2.

**Verification**: all 4 integration tests pass on a system with pandoc;
on a system without pandoc, three pass and one is skipped (not failed).

------------------------------------------------------------------------

## Fix 7 — `R/drift.R`: change `list_snapshots()` default `db_path` to `NULL`

**Line affected**: line 21

``` r
# BEFORE:
list_snapshots <- function(dataset_name = NULL,
                           db_path = "data/snapshots.sqlite") {
  empty <- data.frame(...)
  if (!file.exists(db_path)) return(invisible(empty))

# AFTER:
list_snapshots <- function(dataset_name = NULL,
                           db_path = NULL) {
  if (is.null(db_path))
    rlang::abort('`db_path` must be supplied (e.g. db_path = "data/snapshots.sqlite")')
  empty <- data.frame(...)
  if (!file.exists(db_path)) return(invisible(empty))
```

Also update the `@examples` block to keep it valid (it already uses
[`tempfile()`](https://rdrr.io/r/base/tempfile.html) so no change needed
there).

Update the `@param db_path` documentation to state that the argument is
now required.

**Verification**:
[`list_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/list_snapshots.md)
called without `db_path` throws an informative error.
`list_snapshots(db_path = tempfile(fileext = ".sqlite"))` still returns
an empty data frame.

------------------------------------------------------------------------

## Fix 8 — New tests: T-01 through T-05

### T-01 and T-02 — `tests/testthat/test-report-tempdir.R` (new file)

``` r

library(testthat)
library(dqcheckr)

# Helper shared by T-01 and T-02
run_minimal_render <- function() {
  tmp <- tempdir()
  df  <- data.frame(id = c("1","2"), val = c("10","20"),
                    stringsAsFactors = FALSE)
  cfg <- list(
    format   = "csv",
    rules    = list(max_missing_rate = 0.05, max_non_numeric_rate = 0.01,
                    min_row_count = 0),
    column_rules = list(), key_columns = NULL, expected_columns = NULL
  )
  qc  <- run_qc_checks(df, cfg)
  cs  <- compute_col_stats(df, cfg, qc)
  render_report(
    dataset_name     = "tmpds",
    file_name        = "tmp.csv",
    file_path        = file.path(tmp, "tmp.csv"),
    df               = df,
    qc_results       = qc,
    cp_results       = list(),
    custom_results   = list(),
    snapshot_history = data.frame(),
    config           = cfg,
    col_stats        = cs,
    output_dir       = tmp,
    open_report      = FALSE
  )
}

# T-01: template directory unchanged after rendering
test_that("render_report() leaves no files in the template directory", {
  skip_if_not(rmarkdown::pandoc_available())
  tmpl_dir <- system.file("templates", package = "dqcheckr")
  before   <- sort(list.files(tmpl_dir, all.files = TRUE))
  run_minimal_render()
  after    <- sort(list.files(tmpl_dir, all.files = TRUE))
  expect_equal(after, before)
})

# T-02: all new files created during render are under tempdir()
test_that("render_report() writes intermediate files only under tempdir()", {
  skip_if_not(rmarkdown::pandoc_available())
  tmpl_dir <- system.file("templates", package = "dqcheckr")
  before   <- normalizePath(
    list.files(tmpl_dir, full.names = TRUE, all.files = TRUE))
  run_minimal_render()
  after    <- normalizePath(
    list.files(tmpl_dir, full.names = TRUE, all.files = TRUE))
  new_in_tmpl <- setdiff(after, before)
  expect_length(new_in_tmpl, 0L)
})
```

### T-03 — `tests/testthat/test-report-tempdir.R` (same file, continued)

``` r

# T-03: compare_snapshots(report = TRUE) leaves template directory unchanged
test_that("compare_snapshots(report=TRUE) leaves no files in template directory", {
  skip_if_not(rmarkdown::pandoc_available())
  db      <- make_drift_db(2)   # reuse helper from test-drift.R
  cfg_dir <- make_drift_config()
  tmpl_dir <- system.file("templates", package = "dqcheckr")
  before   <- sort(list.files(tmpl_dir, all.files = TRUE))
  compare_snapshots("test_ds", db_path = db, config_dir = cfg_dir,
                    report = TRUE, open_report = FALSE)
  after    <- sort(list.files(tmpl_dir, all.files = TRUE))
  expect_equal(after, before)
})
```

Note: `make_drift_db()` and `make_drift_config()` are defined in
`test-drift.R`. To avoid duplication, extract them to
`tests/testthat/helper-drift.R` so they are available to both test files
without re-definition.

### T-04 — add to `tests/testthat/test-integration.R`

``` r

# T-04: all output files from run_dq_check() are under tempdir()
test_that("run_dq_check() writes all output files under tempdir()", {
  skip_if_not(rmarkdown::pandoc_available())
  cfg_dir <- setup_integration_env()
  result  <- run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE)
  if (!is.null(result$report_path))
    expect_true(startsWith(normalizePath(result$report_path),
                            normalizePath(tempdir())))
  db_path <- file.path(cfg_dir, "snapshots.sqlite")
  expect_true(startsWith(normalizePath(db_path),
                          normalizePath(tempdir())))
})
```

### T-05 — add to `tests/testthat/test-integration.R`

``` r

# T-05: run_dq_check() returns valid result with report_path=NULL when pandoc absent
test_that("run_dq_check() returns valid result with NULL report_path when pandoc unavailable", {
  cfg_dir <- setup_integration_env()
  withr::with_mocked_bindings(
    pandoc_available = function(...) FALSE,
    .package = "rmarkdown",
    {
      expect_warning(
        result <- run_dq_check("integ_ds", config_dir = cfg_dir, open_report = FALSE),
        "Pandoc not found"
      )
      expect_type(result, "list")
      expect_named(result, c("status", "report_path", "snapshot_id"))
      expect_null(result$report_path)
      expect_false(is.null(result$snapshot_id))
      expect_true(result$snapshot_id >= 1L)
    }
  )
})
```

Note: T-05 requires `withr` (already a common testthat dependency). Add
`withr` to `Suggests` in `DESCRIPTION` if not already present.

------------------------------------------------------------------------

## Fix 9 — `NEWS.md`: document bug fixes under 0.2.0

Add a `## Bug fixes` section to the existing `# dqcheckr 0.2.0` entry:

``` markdown
## Bug fixes

* `render_report()` and `.write_drift_html_report()` now pass `intermediates_dir =
  tempdir()` to `rmarkdown::render()`. Previously, knitr wrote intermediate files
  (`.knit.md`) to the template directory inside the installed package, which caused
  `R CMD check` failures on CRAN Debian builders where the user library is remounted
  read-only during testing (#CRAN-Debian).

* `render_report()` now checks `rmarkdown::pandoc_available()` before attempting to
  render and returns `NULL` invisibly when pandoc is absent, consistent with the
  existing behaviour of `.write_drift_html_report()`. `run_dq_check()` handles this
  gracefully and returns `report_path = NULL` rather than erroring out.

* `list_snapshots()` no longer has a relative-path default for `db_path`. The argument
  is now required; omitting it throws an informative error. Previously the default
  `"data/snapshots.sqlite"` could resolve to a path inside the user library depending
  on the working directory at call time.

* Removed runtime output artefacts (`inst/demonstrations/output2/`) that were
  accidentally committed to the package source. These HTML reports and SQLite database
  file are now excluded via `.Rbuildignore`.
```

------------------------------------------------------------------------

## Verification checklist

Run these checks locally before submitting to CRAN:

``` r

# 1. Full test suite — all tests must pass, T-05 skips if pandoc present (that is OK)
devtools::test()

# 2. Check that template directory is clean after tests run
list.files(system.file("templates", package = "dqcheckr"), all.files = TRUE)
# Must return only: "." ".." "drift_report.Rmd" "report.Rmd"

# 3. R CMD check with --as-cran
devtools::check(args = "--as-cran")

# 4. Confirm inst/demonstrations/output2 is gone
stopifnot(!dir.exists(system.file("demonstrations/output2", package = "dqcheckr")))

# 5. Confirm list_snapshots() errors without db_path
tryCatch(list_snapshots(), error = function(e) message("OK: ", conditionMessage(e)))
```

------------------------------------------------------------------------

## Files changed summary

| File | Change type |
|----|----|
| `R/report.R` | Add pandoc guard + `intermediates_dir = tempdir()` |
| `R/run_check.R` | Handle `NULL` report_path in message and return value |
| `R/drift.R` | Add `intermediates_dir = tempdir()` in `.write_drift_html_report()`; change [`list_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/list_snapshots.md) default |
| `inst/demonstrations/output2/` | Delete entirely |
| `.Rbuildignore` | Add `^inst/demonstrations/output` |
| `tests/testthat/test-integration.R` | Absolute paths in global config; pandoc skip guard; add T-04, T-05 |
| `tests/testthat/test-report-tempdir.R` | New file: T-01, T-02, T-03 |
| `tests/testthat/helper-drift.R` | New file: extract `make_drift_db()` and `make_drift_config()` from `test-drift.R` |
| `tests/testthat/test-drift.R` | Remove `make_drift_db()` and `make_drift_config()` (moved to helper) |
| `DESCRIPTION` | Add `withr` to `Suggests` if not present |
| `NEWS.md` | Add bug fixes section to 0.2.0 entry |
