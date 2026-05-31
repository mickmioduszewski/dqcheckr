# CRAN Debian Write-to-User-Library Diagnosis

**Package**: dqcheckr 0.1.2 (CRAN) / 0.2.0 (in development — same defect present)  
**Date**: 2026-05-31  
**Error class**: Writing outside the R session temporary directory during `R CMD check`

## 0. Actual CRAN Check Output (v0.1.2)

**Failing platforms**: r-devel-linux-x86_64-debian-clang, r-devel-linux-x86_64-debian-gcc,
r-patched-linux-x86_64, r-release-linux-x86_64  
**Passing platforms**: all Fedora Linux, Windows, and macOS flavours (12 total, 8 pass)

**Exact error message**:
```
Error in `file(con, "w")`: cannot open the connection
```

**Full call chain**:
```
render_report()
  → rmarkdown::render()
    → knitr::knit()
      → xfun::write_utf8()    ← fails here: cannot open connection
```

**Failing tests** (all in `test-integration.R`):
- Line 47: `run_dq_check()` returns list with status, report_path, snapshot_id
- Line 55: `run_dq_check()` writes HTML report file to disk
- Line 62: `run_dq_check()` writes snapshot to SQLite database
- Line 69: `run_dq_check()` returns PASS status for clean fixture pair

**Score**: 146 PASS | 4 FAIL | 4 WARN | 0 SKIP

The Fedora/Windows/macOS passes confirm the defect is not in the logic but in
file-system permissions: only the Debian builders remount the user library read-only
during `R CMD check`. This exactly matches the mechanism described in the CRAN email.

---

## 1. The CRAN Policy Violation

CRAN's Debian check infrastructure installs each package into the user library, then
**remounts that user library read-only** before running `R CMD check`. Any code that
executes during the check — tests, examples, vignettes — and attempts to write files to
a path that resolves inside the user library will fail with a permission error.

The CRAN message is precise: "attempts to write to the user library to which all packages
get installed before checking."

---

## 2. Root Cause — `rmarkdown::render()` with `input` inside the user library

### 2a. Primary site: `R/report.R` — `render_report()`

```r
# R/report.R  line 7–8
template <- system.file("templates", "report.Rmd", package = "dqcheckr")
# ...
rmarkdown::render(
  input       = template,      # <── points inside user library
  output_file = out,           # absolute tempdir path — OK
  ...
)
```

`system.file("templates", "report.Rmd", package = "dqcheckr")` returns the absolute path
of the template **inside the installed package**, which on CRAN Debian is inside the
(now read-only) user library:

```
~/.local/share/R/…/dqcheckr/templates/report.Rmd   ← read-only
```

When `rmarkdown::render()` processes an Rmd file it writes **intermediate knit files**
(e.g., `report.knit.md`, session info fragments) to the **same directory as `input`**
by default. That directory is inside the user library. The write fails.

The `output_file` being in tempdir does not help — it controls only where the final HTML
lands; the intermediate files still go next to the template.

Note: the template already sends figures to `tempdir()` via
`fig.path = file.path(tempdir(), "dqcheckr_figs", "")`, confirming awareness of the
tempdir requirement — but the intermediate knit output was overlooked.

### 2b. Secondary site: `R/drift.R` — `.write_drift_html_report()`

```r
# R/drift.R  line 455–470
template <- system.file("templates", "drift_report.Rmd", package = "dqcheckr")
# ...
tmp_out <- file.path(tempdir(), basename(outfile))   # output_file in tempdir — OK
rmarkdown::render(
  input       = template,      # <── still points inside user library
  output_file = tmp_out,
  ...
)
```

Same structural problem. The attempt to route `output_file` to tempdir was a partial fix;
`input` being inside the user library still causes rmarkdown to write intermediate files
there.

---

## 3. Where the Error Surfaces During `R CMD check`

### 3a. Integration test — confirmed trigger

`tests/testthat/test-integration.R` calls `run_dq_check()` with `open_report = FALSE`.
`run_dq_check()` calls `render_report()`, which calls `rmarkdown::render()` as described.
These tests execute unconditionally during `R CMD check` and are the direct trigger for
the CRAN failure on Debian.

### 3b. Drift HTML report — latent trigger

`tests/testthat/test-drift.R` passes `report = FALSE` to all `compare_snapshots()` calls,
so `.write_drift_html_report()` is never reached in those tests. However, the function
contains the same defect. Any future test (or example) that exercises `compare_snapshots()`
with the default `report = TRUE` would fail identically.

### 3c. Vignettes — not a current trigger

Both vignettes (`dqcheckr.Rmd`, `specification.Rmd`) set `eval = FALSE` on all code
chunks. No vignette code runs during `R CMD check`. This is correct and need not change.

### 3d. Examples — not a current trigger

All `@examples` blocks that call write-paths use `tempfile()` or `tempdir()` explicitly,
or are wrapped in `\donttest{}`. No bare example triggers the write error currently.

---

## 4. Secondary Issue — Runtime Output Files Committed to `inst/`

The following runtime output files are committed inside `inst/demonstrations/output2/`:

```
inst/demonstrations/output2/reports/  (10 HTML report files)
inst/demonstrations/output2/snapshots.sqlite
```

These are artefacts of running the demo scripts locally and committing the result.
They should never be inside the package source because:

1. They bloat the installed package unnecessarily.
2. They create a false impression that `inst/demonstrations/output2/` is a valid write
   target. Any code (demo or future test) that uses the demonstration configs
   (`config/dqcheckr.yml` has `snapshot_db: "output/snapshots.sqlite"`,
   `config2/dqcheckr.yml` has `snapshot_db: "output2/snapshots.sqlite"`) and resolves
   those relative paths from inside the installed package directory will attempt to write
   into the user library.

---

## 5. Fragile Relative-Path Pattern in Integration Tests

In `test-integration.R`, `setup_integration_env()` writes a global config with relative
paths:

```r
writeLines(c(
  "snapshot_db: 'data/snapshots.sqlite'",     # relative
  "report_output_dir: 'reports/'",             # relative
  ...
), file.path(cfg, "dqcheckr.yml"))
```

The dataset config (`integ_ds.yml`) overrides these with absolute tempdir paths, and
`load_config()` propagates only the dataset-config value when it is non-NULL. So the
current tests do not actually use the relative paths.

However, this is fragile: if the override mechanism in `load_config()` changes, or a
new test forgets to set absolute paths in the dataset config, the relative paths in the
global config become active and will write `data/snapshots.sqlite` and `reports/` relative
to the test working directory — potentially inside the user library.

---

## 6. Default Parameter in `list_snapshots()`

```r
# R/drift.R  line 21
list_snapshots <- function(dataset_name = NULL,
                           db_path = "data/snapshots.sqlite") {
```

The default `db_path = "data/snapshots.sqlite"` is a relative path. Any code that calls
`list_snapshots()` without an explicit `db_path` will resolve it against the current
working directory. During `R CMD check`, if the working directory is inside the installed
package, this write target lands inside the user library.

The current `@examples` correctly uses `tempfile()`, so no violation exists today.
But the default parameter itself is a standing CRAN policy risk.

---

## 7. Gap Analysis — Tests That Need to Be Added

The following tests are absent and their absence allowed the root-cause defect to reach
CRAN undetected:

| # | Missing test | Why it matters |
|---|---|---|
| T-01 | Test that `render_report()` leaves **no files** in the template's parent directory after rendering | Would have caught the intermediate-file write to user library before submission |
| T-02 | Test that `render_report()` writes intermediate files to `tempdir()` (or a subdirectory thereof) | Directly validates the post-fix behaviour |
| T-03 | Test that `compare_snapshots()` with `report = TRUE` completes without writing to the template directory | Covers the latent defect in `.write_drift_html_report()` |
| T-04 | Test that `run_dq_check()` end-to-end writes **all** output (HTML, SQLite) under `tempdir()` when config paths are in tempdir | Guards against future regressions where a new write path bypasses the tempdir pattern |
| T-05 | Test that no file is written to `system.file("templates", package = "dqcheckr")` during a `run_dq_check()` call | Directly mirrors the Debian check condition |

---

## 8. Summary of Issues by Priority

| Priority | Issue | Location | Fix category |
|---|---|---|---|
| **P1 — Critical** | `rmarkdown::render(input = system.file(...))` writes intermediate files to user library | `R/report.R:24`, `R/drift.R:464` | Code fix |
| **P2 — High** | Integration test unconditionally triggers the P1 write during `R CMD check` | `tests/testthat/test-integration.R` | Test guard / relies on P1 fix |
| **P3 — Moderate** | Runtime output files committed to `inst/demonstrations/output2/` | `inst/` directory | Remove from package |
| **P4 — Moderate** | Global config in integration test uses relative paths as fallback | `tests/testthat/test-integration.R` | Harden test setup |
| **P5 — Moderate** | `list_snapshots()` default `db_path = "data/snapshots.sqlite"` is a relative path | `R/drift.R:21` | Change default |
| **P6 — Low** | No tests validate that renders leave the template directory untouched | Test suite | Add tests T-01 through T-05 |

---

## 9. Confidence Assessment

The P1 issue is the definitive cause of the CRAN Debian failure. The mechanism is
well-established: `rmarkdown::render()` with a read-only `input` directory writes
intermediate files (`.knit.md`) there. This is documented rmarkdown behaviour controlled
by the `intermediates_dir` parameter, which the package does not set. The fix is
deterministic.

The integration test (P2) is the execution path that triggers P1 during `R CMD check`.
Fixing P1 in the source code will also fix the test behaviour.

P3–P6 are real but not the direct cause of the Debian check failure. They represent
hardening work to prevent regressions.
