## R CMD check results

0 errors | 0 warnings | 1 note

## Note

* "checking for future file timestamps ... NOTE: unable to verify current time"
  This note originates from the check environment's inability to resolve an
  external time server. It is not related to the package code. Observed on
  macOS in a sandboxed development environment; not expected to appear on CRAN
  infrastructure.

## Test environments

* macOS 25.5.0 (local), R 4.4.x
* win-builder: R devel (to be checked before submission)

## Package notes

* The package requires the Quarto CLI for HTML report rendering.
  `render_report()` and `compare_snapshots()` emit an informative warning and
  return NULL when Quarto is not available, so the package installs and loads
  without Quarto being present.
* All examples that invoke Quarto, write files, or require a configured dataset
  are wrapped in `\donttest{}`.
