## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

* macOS Tahoe 26.5 / aarch64-apple-darwin23, R 4.6.0 (local)
* win-builder: R devel (checked before submission)

## Package notes

* The package requires the Quarto CLI for HTML report rendering.
  `render_report()` and `compare_snapshots()` emit an informative warning and
  return NULL when Quarto is not available, so the package installs and loads
  without Quarto being present.
* All examples that invoke Quarto, write files, or require a configured dataset
  are wrapped in `\donttest{}`.
