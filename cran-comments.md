## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

* macOS Tahoe 26.5 / aarch64-apple-darwin23, R 4.6.0 (local)
* win-builder: R-devel (2026-05-31 r90090, x86_64-w64-mingw32): results pending

## Previous CRAN submission errors (v0.1.2) — addressed in v0.2.0

The v0.1.2 submission failed with 1 ERROR on CRAN's Debian r-devel server:

  Running 'testthat.R' failed.
  [ FAIL 4 | WARN 4 | SKIP 0 | PASS 146 ]

  Error in `file(con, "w")`: cannot open the connection
  (test-integration.R, via run_dq_check -> render_report -> rmarkdown::render)

Two root causes, both fixed in v0.2.0:

1. Report output directory not created before writing.
   v0.1.2 passed the report_output_dir path to rmarkdown::render() without
   ensuring the directory existed. On CRAN's server the directory was absent,
   causing an unhandled "cannot open the connection" error.

   Fix: render_report() now calls dir.create(output_dir, recursive = TRUE,
   showWarnings = FALSE) before any write attempt.

2. No graceful fallback when Quarto CLI is absent.
   v0.2.0 migrated reports from rmarkdown to Quarto. render_report() now
   checks quarto::quarto_available() and returns NULL with an informative
   warning when the CLI is not installed, so the package installs, loads,
   and runs quality checks cleanly on servers without Quarto.

   Integration tests that do not exercise the report (status, snapshot_id
   checks) now wrap run_dq_check() in suppressWarnings() to avoid spurious
   WARN entries from the expected "Quarto not available" warning on CRAN
   servers. The test that checks the HTML report file is guarded with
   skip_if_not(quarto::quarto_available()).

## Package notes

* The package requires the Quarto CLI for HTML report rendering.
  render_report() and compare_snapshots() emit an informative warning and
  return NULL when Quarto is not available, so the package installs and loads
  without Quarto being present.
* All examples that invoke Quarto, write files, or require a configured dataset
  are wrapped in \donttest{}.
