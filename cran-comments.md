## Resubmission — fixing CRAN Debian check errors

This is a resubmission of dqcheckr. Version 0.1.2 produced 4 ERRORs on the
Debian CRAN builders (r-devel-linux-x86_64-debian-clang/gcc,
r-patched-linux-x86_64, r-release-linux-x86_64).

### Root cause and fix

`rmarkdown::render()` was called with `input` pointing to a template file
inside the installed package. knitr writes intermediate files (`.knit.md`)
to the same directory as `input` by default. On Debian builders the user
library is remounted read-only during `R CMD check`, causing the write to
fail with "cannot open the connection".

Fix: `intermediates_dir = tempdir()` is now passed to both `rmarkdown::render()`
calls in the package, routing all intermediate output to the session temporary
directory. A `pandoc_available()` guard was also added so the function
degrades gracefully rather than erroring when pandoc is absent.

### Additional changes in 0.2.0

New features: per-column type overrides (`column_types`), per-column
threshold overrides in `column_rules`, `compare_snapshots()` for historical
drift comparison, and `list_snapshots()`.

## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

* macOS 26.5 (local), R 4.5.2, aarch64-apple-darwin20
* R-hub (via rhub.yaml): Linux R-devel, Windows R-devel, macOS arm64 R-devel

## Spell check

No spelling errors found (devtools::spell_check()).

## URL check

All URLs correct (urlchecker::url_check()).

## Reverse dependencies

dqcheckr has no reverse dependencies.
