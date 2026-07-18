# CRAN submission comments — dqcheckr 0.2.5

## R CMD check results

0 errors | 0 warnings | 1 note

This is a bug-fix and robustness update (v0.2.5) of a package currently on CRAN
as v0.2.2. The intervening 0.2.3 and 0.2.4 versions were internal development
milestones and were not submitted to CRAN.

## Test environments

* macOS 15 / aarch64-apple-darwin, R 4.6.0, checked via
  `rcmdcheck::rcmdcheck("dqcheckr_0.2.5.tar.gz", args = "--as-cran")` (local,
  2026-07-19): 0 errors | 0 warnings | 1 note
* win-builder: R-devel (R Under development (unstable), 2026-07-17 r90265 ucrt):
  Status OK — 0 errors | 0 warnings | 0 notes
* win-builder: R-release (R 4.6.1, 2026-06-24 ucrt):
  Status OK — 0 errors | 0 warnings | 0 notes

## Notes

* "Skipping checking HTML validation: 'tidy' doesn't look like recent enough
  HTML Tidy."
  This is a local tooling issue (outdated `tidy` binary on the check machine,
  used only for validating the rendered HTML manual). It does not appear on
  CRAN's check servers and has appeared identically in every local check of
  this package since v0.2.0.

## What changed since v0.2.2

* Bug fixes from an internal quality review:
  * The numeric-mean-shift comparison no longer aborts the run when a numeric
    column contains a literal `Inf`/`-Inf` value (finite values are filtered
    before the mean is taken).
  * `compare_snapshots()` rejects a `NULL`/empty `dataset_name` with an
    informative typed error instead of an empty-message abort.
  * `read_recent_snapshots()` clamps a negative `n` to 0 rather than returning
    the whole history (SQLite reads `LIMIT -1` as unbounded).
* Robustness introduced across 0.2.3–0.2.5: a zero-row delivery now completes
  and reports FAIL (rather than aborting); snapshot writes are transactional;
  the `render_status` column carries a `"pending"` state until the report is
  confirmed written, so a consumer never links a report that does not exist;
  report and drift filenames include the snapshot id(s) to prevent same-second
  collisions; full-file UTF-8 encoding validation; and shared error handling
  for the Quarto render pipeline.
* Config values and custom-check results are validated with informative typed
  errors; report files are moved with a copy fallback across filesystems.
* See NEWS.md for the full list.

## Reverse dependencies

'dqcheckrGUI' (same maintainer) is on CRAN and Imports dqcheckr (>= 0.2.2).
It was checked against this version locally: 0 errors | 0 warnings, full test
suite passes. All schema additions since 0.2.2 are backward compatible (column
auto-migration; no changed exported function signatures or return shapes).

## Package notes

* The package requires the Quarto CLI for HTML report rendering.
  `render_report()` and `compare_snapshots()` return `NULL` with an informative
  warning when Quarto is not available, so the package installs and runs all
  quality checks cleanly on servers without the CLI.
* All examples that invoke Quarto, write files, or require a configured dataset
  are wrapped in `\donttest{}`; the pipeline integration tests are additionally
  `skip_on_cran()` so check wall time is bounded regardless of whether Quarto is
  present on the check machine.
