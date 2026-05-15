## Resubmission

This is a resubmission addressing the reviewer's comments:

* Software names ('SQLite', 'CSV', 'HTML', 'YAML') are now quoted in the
  Title, Description, and package-level documentation.

* All `\dontrun{}` blocks have been replaced. Examples that operate on
  in-memory data frames are now fully unwrapped. The `run_dq_check()`
  example, which renders an HTML report and is expected to exceed 5 seconds,
  uses `\donttest{}`. All examples use bundled demonstration data via
  `system.file()` and run cleanly under `R CMD check --run-donttest` on all
  platforms including Windows.

* No academic references describe the methods in this package; the checks
  are standard data quality engineering practices with no associated
  literature.

## R CMD check results

0 errors | 0 warnings | 1 note

* NOTE: checking for non-standard things in the check directory.
  Found files/directories: 'data' 'reports'
  These are output files written by the `run_dq_check()` \donttest{} example
  (a snapshot SQLite database and an HTML report). They are written to
  tempdir() and do not affect the package.

## Test environments

* macOS (local), R 4.5.2, aarch64-apple-darwin20 — 0 errors, 0 warnings, 4 notes
* R-hub: Linux (R-devel) — 0 errors, 0 warnings, 1 note
* R-hub: Windows (R-devel) — 0 errors, 0 warnings, 1 note
* R-hub: macOS arm64 (R-devel) — 0 errors, 0 warnings, 1 note

## Spell check

No spelling errors found (devtools::spell_check()).

## URL check

All URLs correct (urlchecker::url_check()).

## Reverse dependencies

dqcheckr has no reverse dependencies (new submission).
