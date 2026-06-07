## R CMD check results

0 errors | 0 warnings | 0 notes

This is a resubmission (v0.2.1, a patch release over the accepted v0.2.0).

## Test environments

* macOS Tahoe 26.5 / aarch64-apple-darwin23, R 4.6.0 (local): 0 errors | 0 warnings | 0 notes
* win-builder: R-devel, Windows Server 2022 (to be re-run before submission;
  results will be attached here)

## Notes

None outstanding. The previous local-only NOTE about an outdated 'tidy'
binary on the check machine ("Skipping checking HTML validation: 'tidy'
doesn't look like recent enough HTML Tidy") does not reproduce in this
check run and does not appear on CRAN's check servers in any case.

## What changed since v0.2.0

* Bug fixes to filename/timestamp consistency (UTC slugs matching the
  snapshot DB), the CP-07 type-change comparison guard, and config-key
  forwarding (`col_names`, `quote_char`) to `readr::read_delim()`.
* Removed dead code (`read_pass_rate_trend()`).
* All `rlang::abort()` calls now carry typed, two-level error classes
  (`c("<specific>", "dqcheckr_error")`) so callers can catch errors
  structurally.
* Test-suite consolidation (shared fixtures, regexp-guarded `expect_error()`,
  removed redundant `library()` calls).
* See NEWS.md for the full list.

## Previous CRAN submission errors (v0.1.2) — addressed in v0.2.0

### CRAN policy violation: writes to user library during checks

CRAN's Debian check servers remount the user library read-only before running
checks. v0.1.2 violated the CRAN policy on filesystem writes because
rmarkdown::render() was called with the Rmd template resolved via
system.file(), which resolves to the installed package directory inside the
user library. knitr then attempted to write intermediate files (the .knit.md
scratch file) adjacent to the template, hitting the read-only mount and
producing:

  Error in file(con, "w"): cannot open the connection

This was the direct cause of all 4 test failures in test-integration.R.

### Fix in v0.2.0

Reports have been migrated from rmarkdown to Quarto. The key change in
render_report() and the drift equivalent .write_drift_html_report() is that
the .qmd template is first copied to an isolated tempfile() directory before
quarto::quarto_render() is called. Quarto and knitr write all intermediate
and output files to that temp directory. Nothing is written to or near the
package installation path.

Additionally, render_report() now checks quarto::quarto_available() at the
top of the function and returns NULL with an informative warning when the
Quarto CLI is not installed. This means the package installs, loads, and runs
all quality checks cleanly on servers without the Quarto CLI.

Integration tests that do not exercise the HTML report path (status and
snapshot_id assertions) now wrap run_dq_check() in suppressWarnings() to
avoid spurious WARN entries from the expected "Quarto not available" warning
emitted on servers without the CLI.

## Package notes

* The package requires the Quarto CLI for HTML report rendering.
  render_report() and compare_snapshots() return NULL with an informative
  warning when Quarto is not available, so the package installs and runs
  without the CLI being present.
* All examples that invoke Quarto, write files, or require a configured
  dataset are wrapped in \donttest{}.
