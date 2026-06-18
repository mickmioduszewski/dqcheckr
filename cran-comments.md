## R CMD check results

0 errors | 0 warnings | 1 note

This is a maintenance update (v0.2.2) of a package currently on CRAN as
v0.2.1.

## Test environments

* macOS Tahoe 26.5 / aarch64-apple-darwin23, R 4.6.0, checked via
  `rcmdcheck::rcmdcheck(<built tarball>, args = "--as-cran")` (local):
  0 errors | 0 warnings | 1 note
* win-builder: R-devel (R Under development (unstable), 2026-06-17 r90169
  ucrt): Status OK -- 0 errors | 0 warnings | 0 notes
* win-builder: R-release (R 4.6.0 ucrt): Status OK -- 0 errors | 0 warnings
  | 0 notes

## Notes

* "Skipping checking HTML validation: 'tidy' doesn't look like recent enough
  HTML Tidy."
  This is a local tooling issue (outdated `tidy` binary on the check
  machine, used only for validating the rendered HTML manual). It does not
  appear on CRAN's check servers and has appeared identically in every local
  check of this package since v0.2.0.

## What changed since v0.2.1

* New optional CSV config key `csv_skip` (parallel to the existing
  `fwf_skip`): `read_dataset()` forwards it as `skip =` to
  `readr::read_delim()`, so a config can supply an explicit `col_names` list
  *and* drop the file's original header row. Defaults to `0L`, so existing
  configs are byte-for-byte unaffected.
* Internal quality polish: `?dqcheckr` package help now resolves, an
  out-of-range `csv_skip` edge case is tested, and all negative tests assert
  on a typed error class. No user-facing behaviour change.
* See NEWS.md for the full list.

## Reverse dependencies

None on CRAN.

## Package notes

* The package requires the Quarto CLI for HTML report rendering.
  `render_report()` and `compare_snapshots()` return `NULL` with an
  informative warning when Quarto is not available, so the package installs
  and runs all quality checks cleanly on servers without the CLI.
* All examples that invoke Quarto, write files, or require a configured
  dataset are wrapped in `\donttest{}`.
