# CRAN submission comments — dqcheckr 0.2.3

## R CMD check results

0 errors | 0 warnings | 1 note

This is a bug-fix update (v0.2.3) of a package currently on CRAN as v0.2.2.

## Test environments

* macOS Tahoe 26.5.1 / aarch64-apple-darwin23, R 4.6.0 (2026-04-24), checked
  via `rcmdcheck::rcmdcheck(<pkg dir>, args = "--as-cran")` (local,
  2026-07-04): 0 errors | 0 warnings | 1 note
* win-builder: R-devel (submitted 2026-07-04): results awaited

## Notes

* "Skipping checking HTML validation: 'tidy' doesn't look like recent enough
  HTML Tidy."
  This is a local tooling issue (outdated `tidy` binary on the check
  machine, used only for validating the rendered HTML manual). It does not
  appear on CRAN's check servers and has appeared identically in every local
  check of this package since v0.2.0.

## What changed since v0.2.2

* Bug fixes from an internal quality review — most importantly, a delivery
  file with zero data rows (e.g. a header-only CSV) no longer aborts
  `run_dq_check()` with an uninformative error; it now completes and reports
  FAIL with a snapshot and report, which is the behaviour a data-quality
  tool should have for an empty delivery.
* Robustness: snapshot writes are transactional; user-supplied custom-check
  results and config values (`column_order_severity`, regex patterns) are
  validated with informative typed errors; report files are moved with a
  copy fallback across filesystems.
* New `report_file` column in the snapshot database (auto-migrated) stores
  the rendered report filename, so consumers no longer reconstruct it from
  the run timestamp.
* Performance: column types are inferred once per data frame and shared
  across all checks via new optional `types` arguments (backward
  compatible — no existing behaviour changed).
* See NEWS.md for the full list.

## Reverse dependencies

'dqcheckrGUI' (same maintainer) is on CRAN and Imports dqcheckr (>= 0.2.2).
It was checked against this version locally: 0 errors | 0 warnings, full
test suite passes. All 0.2.3 schema additions are backward compatible
(column auto-migration; no changed function signatures or return shapes).

## Package notes

* The package requires the Quarto CLI for HTML report rendering.
  `render_report()` and `compare_snapshots()` return `NULL` with an
  informative warning when Quarto is not available, so the package installs
  and runs all quality checks cleanly on servers without the CLI.
* All examples that invoke Quarto, write files, or require a configured
  dataset are wrapped in `\donttest{}`; the pipeline integration tests are
  additionally `skip_on_cran()` so check wall time is bounded regardless of
  whether Quarto is present on the check machine.
