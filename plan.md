# dqcheckr 0.2.0 — Implementation Plan

## Source material

Analysed from `kiro1/dqcheck01/`:

- `feature-change.md` — three formal feature requests
- `drift02.R` — working prototype of Feature 3 (drift comparison)
- `templates/drift_report_v2.Rmd` — working HTML template for drift report
- `config/dqcheckr.yml`, `config/RBB-Extended-BondsLodged.yml`,
  `config/RBB-Extended-RefundsPaid.yml` — real-world YAML demonstrating pain points
- `custom/rbb_extended_checks.R` — example custom checks
- `log2026-05-30.md` — full workflow log including root-cause diagnosis of
  false-positive check outcomes that motivated Features 1 and 2
- `run_dq.R`, `setup_snapshots.R` — caller scripts

---

## How the existing workflow and new features relate

### Two-file mode (`current_file` + `previous_file` in YAML) — unchanged

`run_dq_check()` reads both files, runs QC checks on the current file, runs
CP-01 to CP-08 comparing current to previous, and writes everything into the
**single existing HTML report**. A snapshot is saved to SQLite for the current
file only. This behaviour is identical in 0.2.0.

The only visible differences from 0.2.0 features:
- CP-02 type-change WARNs are suppressed for columns with `column_types` overrides
  (Feature 1)
- CP-03/04/07 thresholds respect per-column `column_rules` entries (Feature 2)
- The report structure, file count, and function signature are unchanged

### Folder mode (`folder` in YAML) — unchanged

`detect_files()` picks the two most recently modified files in the folder as
current and previous. Same pipeline as two-file mode. Unchanged in 0.2.0.

### Snapshot drift comparison (`compare_snapshots()`) — new, separate

`compare_snapshots()` is a new independent function. It is not called by
`run_dq_check()` and does not modify the existing report. It reads two
historical snapshots from SQLite and produces a **separate drift HTML report**.
The original files do not need to be present.

Typical workflow:

```r
# Existing workflow — unchanged
run_dq_check("RBB-Extended-BondsLodged", config_dir = "config")
# → one HTML report (QC + CP checks), one new snapshot row in SQLite

# New in 0.2.0 — called separately, on demand
compare_snapshots("RBB-Extended-BondsLodged",
                  snapshot_id_prev = 1, snapshot_id_curr = 7,
                  config_dir = "config")
# → separate drift HTML report; existing report untouched
```

---

## Test data

Real RBB-Extended input files (166k–168k rows each) are available locally at:

```
kiro1/dqcheck01/input-data/RBB/
  2025/January/Extended Extract/  — Jan 2025 BondsLodged (R1109) and RefundsPaid (R1110)
  2026/January/Extended Extract/  — Jan 2026 BondsLodged and RefundsPaid
```

These files **must not enter the repository** (they contain personal data: names,
phone numbers, email addresses, addresses). They may be used during local
development for manual/smoke testing, but:

- All automated tests (`tests/testthat/`) use only the existing bundled demo data
  (`inst/demonstrations/`) or synthetic data constructed inline.
- `.gitignore` already excludes the `input-data/` path (it is outside the repo).
- No file paths to these files appear in any committed code or test.

Where a test needs a column that would behave like `TenantPhone` or `PremisesPostCode`
(mostly-numeric-but-semantically-character), construct a small synthetic vector
inline (e.g. `c("0412345678", "0298765432", "Unit 3A")`).

---

## Summary of features

| # | Feature | Priority | Status |
|---|---------|----------|--------|
| 1 | Per-column type override (`column_types` in dataset YAML) | High | New |
| 2 | Per-column threshold overrides (extensions to `column_rules`) | Medium | New |
| 3 | Snapshot-to-snapshot drift comparison (`compare_snapshots()`, `list_snapshots()`) | Medium | Prototype exists in `drift02.R` |

---

## Analysis and observations

### Feature 1 — Per-column type override

**Motivation (from log):** The RBB-Extended datasets have columns like `LandlordUnit`,
`TenantPhone`, and postcode columns that are predominantly numeric in *value* but
semantically character. The automatic type inference (threshold 90%) classifies them
as `numeric`, causing:
- CP-02 WARN on type change when the non-numeric rate drifts across the threshold year-to-year
- CP-04 false mean-shift WARNs on phone numbers
- CP-07 false non-numeric rate WARNs
- QC-11 non-numeric flags on valid values like "Unit 3A"

**Design:** A `column_types` map in the dataset YAML overrides inference per column.
The cleanest implementation is a single helper `resolve_col_type(col, x, config)`
that checks `config$column_types[[col]]` first, then falls back to `infer_col_type()`.
This keeps the change localised — every function that currently calls `infer_col_type()`
directly is changed to call `resolve_col_type()` instead, passing the column name
and config.

**Scope of effect:** When a column is forced to `character`:
- QC-06 reports the overridden type (not inferred)
- QC-07 (numeric stats) skips it
- QC-11 (non-numeric rate) skips it
- CP-02 uses the override for type comparison (eliminates false type-change WARNs)
- CP-04 (mean shift) skips it
- CP-07 (non-numeric rate change) skips it
- CP-05/CP-06 (new/dropped distinct values) treat it as character
- `compute_col_stats()` stores the overridden type as `inferred_type` in SQLite
  so that drift comparisons also see the override

When forced to `numeric` (reverse case — forcing a mixed column to numeric):
- QC-07, QC-11, CP-04, CP-07 all run as if it were numeric
- Useful if a column has a very low non-numeric rate and you know they are errors

When forced to `date`: only the universal checks (missing rate, distinct count)
apply. No numeric stats, no non-numeric checks.

**Ambiguities to resolve:**
1. Valid values are `character`, `numeric`, `date` — should the package validate
   the value and abort on invalid types? **Yes** — fail loudly in `load_config()`
   or `resolve_col_type()`.
2. `date` override: the feature request describes it but gives no example. Treat
   it symmetrically — a date-forced column is skipped by numeric and character
   checks, consistent with how inferred dates are handled.
3. `compute_col_stats()` currently calls `infer_col_type()` directly and branches
   on `col_type == "numeric"`. It needs to call `resolve_col_type()` instead so
   the SQLite snapshot records the correct type.

---

### Feature 2 — Per-column threshold overrides

**Motivation (from log):** `LandlordEmail` is 99% missing by design (the system
doesn't require it). With a global 5% missing threshold it always FAILs. Similarly
`BondAmount` should have 0% missing but the global 5% threshold is too lenient.

**Design:** Extend the existing `column_rules` map (already used for `min_value`,
`max_value`, `pattern`, `allowed_values`) with threshold keys. Resolution order:

```
column_rules.<col>.<threshold>  >  rule_overrides.<threshold>  >  default_rules.<threshold>
```

Implement as a helper `col_threshold(config, col, key, default)` that encodes this
three-level fallback.

**Supported threshold keys and the checks they affect:**

| YAML key | Check | Current behaviour |
|---|---|---|
| `max_missing_rate` | QC-01 | Global via `config$rules$max_missing_rate` |
| `max_non_numeric_rate` | QC-11 | Global via `config$rules$max_non_numeric_rate` |
| `max_missing_rate_change_pp` | CP-03 | Global via `config$rules$max_missing_rate_change_pp` |
| `max_numeric_mean_shift_pct` | CP-04 | Global via `config$rules$max_numeric_mean_shift_pct` |
| `max_non_numeric_rate_change_pp` | CP-07 | Global via `config$rules$max_non_numeric_rate_change_pp` |

**Backwards compatibility:** Entirely additive. Configs without per-column thresholds
are unchanged.

**Ambiguities to resolve:**
1. QC-11 currently computes a single global threshold for all numeric columns. With
   per-column thresholds, the function must look up the threshold inside the column
   loop. This changes the internal structure of `check_non_numeric()` slightly.
2. CP-03, CP-04, CP-07 are already per-column loops; the threshold lookup becomes
   a one-liner inside each loop.
3. What about `max_missing_rate` in CP-03 vs `max_missing_rate_change_pp`? These
   are different keys for different checks — `max_missing_rate` governs QC-01 (absolute
   rate), `max_missing_rate_change_pp` governs CP-03 (change in rate). A column can
   have both set independently. No ambiguity once clearly named.
4. The threshold reported in the `dq_result` object should reflect the *effective*
   threshold (the per-column one if set), so the HTML report is accurate.

---

### Feature 3 — Snapshot-to-snapshot drift comparison

**Motivation:** The existing version comparison (CP-01 to CP-08) compares two
*files* in a single run. `drift02.R` was built to compare two *snapshots stored
in SQLite*, enabling arbitrary historical comparisons without the original files.

**Decision:** Implement Option A (new exported functions). Option B (extend the
existing HTML report) would conflate two different workflows.

**Functions to export:**

```r
list_snapshots(dataset_name = NULL, db_path = "data/snapshots.sqlite")
compare_snapshots(dataset_name, snapshot_id_prev = NULL, snapshot_id_curr = NULL,
                  db_path = "data/snapshots.sqlite", config_dir = NULL,
                  report = TRUE, open_report = interactive())
```

**Internal functions (not exported):**
- `compute_drift()` — all comparison logic, returns a named list (matches drift02.R)
- `write_drift_text_report()` — text output
- `write_drift_html_report()` — renders Rmd template

**Threshold source:** `compare_snapshots()` accepts `config_dir = NULL`. If supplied,
thresholds are read from `dqcheckr.yml`. If `NULL`, package defaults are used
(`max_missing_rate_change_pp = 2.0`, etc.). This makes the function usable without
the YAML files being present (e.g. after files are archived).

**Return value of `compare_snapshots()`:** The named list from `compute_drift()`
(invisibly), with a one-line console summary. Mirrors the pattern of `run_dq_check()`.

**Template location:** `inst/templates/drift_report.Rmd` (adapted from
`drift_report_v2.Rmd`). Accessed via `system.file()` inside the package.

**`list_snapshots()` return value:** A data frame (invisibly), printed to console
if called interactively or directly (standard R convention).

**Critical bug fixed from drift02.R:** `get_snapshots()` and `list_snapshots()`
in `drift02.R` use `sprintf()` to interpolate `dataset_name` directly into SQL.
This is a SQL injection risk. The package implementation must use parameterized
queries (DBI `?` binding), matching the existing pattern in `read_recent_snapshots()`.

**Ambiguities to resolve:**
1. `compare_snapshots()` default (no IDs supplied): use latest vs second-latest
   *by ID sequence*. The feature spec confirms this. When IDs are explicit, respect
   caller order regardless of which is numerically larger.
2. The drift HTML report uses `kableExtra` — already a declared dependency.
3. `write_drift_html_report()` currently writes to `tempdir()` then copies. This
   is because `rmarkdown::render()` renders in the template directory by default.
   Keep this pattern for safety.
4. Should `compare_snapshots()` produce a text report by default? **No** — only
   HTML (matching the approach of `run_dq_check()`). Text report is available
   as an option or internal utility. Add a `text_report = FALSE` parameter.

---

## Files to change or create

### Modified files

| File | Changes |
|---|---|
| `R/utils.R` | Add `resolve_col_type()` and `col_threshold()` helpers; update `load_config()` to validate `column_types` values |
| `R/checks_generic.R` | Update QC-06, QC-07, QC-08, QC-11 to use `resolve_col_type()`; update QC-01, QC-11 to use `col_threshold()` |
| `R/compare.R` | Update CP-02, CP-04, CP-05, CP-06, CP-07 to use `resolve_col_type()`; update CP-03, CP-04, CP-07 to use `col_threshold()` |
| `R/snapshot.R` | Update `compute_col_stats()` to use `resolve_col_type()` |
| `DESCRIPTION` | Bump version to `0.2.0` |
| `NEWS.md` | Add 0.2.0 section |
| `vignettes/dqcheckr.Rmd` | Document `column_types`, per-column thresholds, `compare_snapshots()`, `list_snapshots()` with examples |
| `inst/demonstrations/config/starwars_csv.yml` | Add example `column_types` entry for demo purposes |

### New files

| File | Purpose |
|---|---|
| `R/drift.R` | `compare_snapshots()`, `list_snapshots()`, `compute_drift()`, `write_drift_text_report()`, `write_drift_html_report()` |
| `inst/templates/drift_report.Rmd` | HTML template for drift report (adapted from `drift_report_v2.Rmd`) |
| `tests/testthat/test-type-override.R` | Tests for Feature 1 |
| `tests/testthat/test-col-threshold.R` | Tests for Feature 2 |
| `tests/testthat/test-drift.R` | Tests for Feature 3 |
| `man/compare_snapshots.Rd` | Auto-generated by roxygen2 |
| `man/list_snapshots.Rd` | Auto-generated by roxygen2 |
| `man/resolve_col_type.Rd` | Auto-generated (exported helper) |

---

## Detailed implementation steps

### Step 1 — `resolve_col_type()` helper (R/utils.R)

```r
resolve_col_type <- function(col, x, config) {
  override <- (config$column_types %||% list())[[col]]
  if (!is.null(override)) return(override)
  infer_col_type(x, config$rules$type_inference_threshold %||% 0.90)
}
```

Add to `load_config()`: after merging rules, validate `column_types` values:

```r
valid_types <- c("character", "numeric", "date")
ct <- dataset_cfg$column_types %||% list()
bad <- setdiff(unlist(ct), valid_types)
if (length(bad) > 0)
  rlang::abort(sprintf("Invalid column_types value(s): %s. Must be one of: %s",
                       paste(bad, collapse = ", "), paste(valid_types, collapse = ", ")))
```

Export `resolve_col_type()` so users can call it in custom check scripts.

---

### Step 2 — `col_threshold()` helper (R/utils.R)

```r
col_threshold <- function(config, col, key, default = NULL) {
  col_val <- (config$column_rules %||% list())[[col]][[key]]
  if (!is.null(col_val)) return(col_val)
  rule_val <- config$rules[[key]]
  if (!is.null(rule_val)) return(rule_val)
  default
}
```

This is internal (`@keywords internal`).

---

### Step 3 — Update checks_generic.R

**QC-06 `check_inferred_types()`:** Replace `infer_col_type(df[[col]], threshold)`
with `resolve_col_type(col, df[[col]], config)`. Add "(overridden)" note to the
message if an override was applied.

**QC-07 `check_numeric_stats()`:** Replace the `infer_col_type()` guard with
`resolve_col_type(col, df[[col]], config) != "numeric"`.

**QC-08 `check_distinct_counts()`:** Same pattern — use `resolve_col_type()`.

**QC-11 `check_non_numeric()`:**
- Replace `infer_col_type()` guard with `resolve_col_type()`.
- Replace `threshold <- config$rules$max_non_numeric_rate %||% 0.01` with
  per-column lookup *inside* the loop:
  `threshold <- col_threshold(config, col, "max_non_numeric_rate", 0.01)`
- Update the `threshold` field in `dq_result` to reflect the effective value.

**QC-01 `check_missing_rate()`:** Per-column threshold lookup inside the loop:
```r
threshold <- col_threshold(config, col, "max_missing_rate", 0.05)
```

---

### Step 4 — Update compare.R

**CP-02 `compare_schema()`:** Replace both `infer_col_type()` calls with
`resolve_col_type(col, df_current[[col]], config)` and
`resolve_col_type(col, df_previous[[col]], config)`.

**CP-04 `compare_numeric_mean()`:**
- Replace `infer_col_type()` guards with `resolve_col_type()`.
- Per-column threshold inside the loop:
  `threshold <- col_threshold(config, col, "max_numeric_mean_shift_pct", 0.20)`

**CP-05/CP-06 `compare_new_values()` / `compare_dropped_values()`:** Replace
`infer_col_type()` with `resolve_col_type()`.

**CP-03 `compare_missing_rate()`:** Per-column threshold inside the loop:
`max_change_pp <- col_threshold(config, col, "max_missing_rate_change_pp", 2.0)`

**CP-07 `compare_non_numeric_rate()`:** 
- Replace `infer_col_type()` guards with `resolve_col_type()`.
- Per-column threshold:
  `threshold <- col_threshold(config, col, "max_non_numeric_rate_change_pp", 1.0)`

---

### Step 5 — Update snapshot.R

**`compute_col_stats()`:** Replace `infer_col_type(x, type_threshold)` with
`resolve_col_type(col, x, config)`. The `col_type` used for branching and the
`value` stored in the `inferred_type` row both reflect the override.

---

### Step 6 — New file: R/drift.R

Structure mirrors drift02.R but adapted for package conventions:

```r
# Exported

#' List available snapshots
#' @export
list_snapshots <- function(dataset_name = NULL,
                           db_path = "data/snapshots.sqlite") { ... }

#' Compare two snapshots from the SQLite database
#' @export
compare_snapshots <- function(dataset_name,
                              snapshot_id_prev = NULL,
                              snapshot_id_curr = NULL,
                              db_path = "data/snapshots.sqlite",
                              config_dir = NULL,
                              report = TRUE,
                              text_report = FALSE,
                              open_report = interactive()) { ... }

# Internal

.load_drift_thresholds <- function(config_dir = NULL) { ... }
.compute_drift <- function(con, dataset_name, id_prev, id_curr, thresholds) { ... }
.write_drift_text_report <- function(drift, outfile) { ... }
.write_drift_html_report <- function(drift, outfile, report_dir) { ... }
```

Key implementation notes:
- Use DBI parameterized queries throughout (no `sprintf()` for SQL).
- `list_snapshots()` returns the data frame invisibly; if called at the top level
  interactively it prints (standard R data-frame behaviour via `invisible()`).
- `compare_snapshots()` returns the drift list invisibly.
- The HTML template path: `system.file("templates/drift_report.Rmd", package = "dqcheckr")`.
- Console output: one line only —
  `[dqcheckr] drift: <dataset> snapshot #<prev> vs #<curr> | <html_path>`

---

### Step 7 — New file: inst/templates/drift_report.Rmd

Adapt `drift_report_v2.Rmd` from the prototype:
- Same structure (header, table-level drift, schema drift, per-column drift tables)
- Use `system.file()` for any asset paths
- Parameterised via `params: list(drift = NULL)` (identical to prototype)
- No path hardcoding

---

### Step 8 — Tests

#### test-type-override.R

```
- resolve_col_type() returns override when column_types is set
- resolve_col_type() calls infer_col_type() when no override
- resolve_col_type() "date" override returns "date"
- load_config() aborts on invalid column_types value (e.g. "integer")
- QC-06: message includes "(overridden)" when type is forced
- QC-06: reports forced type, not inferred type
- QC-07: skips a character-forced column that would otherwise be inferred numeric
- QC-11: skips a character-forced column
- CP-02: no type-change WARN when override stabilises the type
- CP-04: skips a character-forced column
- CP-07: skips a character-forced column
- compute_col_stats(): stores overridden type in inferred_type row
- compute_col_stats(): does not compute numeric stats for character-forced column
```

#### test-col-threshold.R

```
- col_threshold() returns column-level value when present
- col_threshold() falls back to config$rules when no column entry
- col_threshold() falls back to default when neither present
- QC-01: uses per-column max_missing_rate (column with 1.00 passes; global 0.05 would fail)
- QC-01: uses global threshold for columns not in column_rules
- QC-11: uses per-column max_non_numeric_rate
- CP-03: uses per-column max_missing_rate_change_pp
- CP-04: uses per-column max_numeric_mean_shift_pct
- CP-07: uses per-column max_non_numeric_rate_change_pp
- dq_result threshold field reflects effective (per-column) threshold
```

#### test-drift.R

```
- list_snapshots() returns empty data frame for non-existent DB
- list_snapshots() returns empty data frame for DB with no matching dataset
- list_snapshots() returns correct columns: id, dataset_name, file_name,
  run_timestamp, row_count, overall_status
- list_snapshots(NULL) returns all datasets
- list_snapshots("x") filters to dataset "x"
- compare_snapshots() errors if < 2 snapshots exist
- compare_snapshots() errors if same ID passed for prev and curr
- compare_snapshots() uses second-latest vs latest when IDs not supplied
- compare_snapshots() respects explicit ID order (first = prev even if numerically larger)
- compute_drift() table_drift: row count change correct
- compute_drift() schema_changes: new column detected
- compute_drift() schema_changes: dropped column detected
- compute_drift() schema_changes: type change detected
- compute_drift() missing_rate_changes: filtered and sorted by magnitude
- compute_drift() missing_rate_changes: exceeds flag set correctly
- compute_drift() non_numeric_changes: computed correctly
- compute_drift() mean_shifts: computed correctly; NA when prev mean is 0
- compute_drift() distinct_changes: filtered to changed only
- compare_snapshots() returns list with expected elements invisibly
- list_snapshots() uses parameterized SQL (no injection risk)
```

---

### Step 9 — Documentation

**vignette/dqcheckr.Rmd:** Add three new sections:

1. **Per-column type overrides** — YAML example, use cases table from feature-change.md,
   note that `resolve_col_type()` is also available for custom check scripts.
2. **Per-column threshold overrides** — YAML example showing `LandlordEmail`
   (max_missing_rate: 1.00) and `BondAmount` (max_missing_rate: 0.00).
3. **Historical drift analysis** — `list_snapshots()` and `compare_snapshots()`
   examples, workflow (run_dq_check → run_dq_check → compare_snapshots).

**Function documentation (roxygen2):**
- `resolve_col_type()` — exported; document `column_types` YAML key
- `compare_snapshots()` — full parameter docs, return value, `\donttest{}` example
- `list_snapshots()` — full parameter docs, return value, example

---

### Step 10 — DESCRIPTION, NEWS, cran-comments

**DESCRIPTION:** `Version: 0.2.0`

**NEWS.md:** Add section:

```
# dqcheckr 0.2.0

## New features

* Per-column type overrides (`column_types` in dataset YAML). Columns can be
  forced to `character`, `numeric`, or `date` regardless of inferred type.
  Eliminates false QC-11, CP-02, CP-04, and CP-07 findings on phone numbers,
  postcodes, unit numbers, and similar semantically-character columns.

* Per-column threshold overrides (`column_rules` extensions). QC-01, QC-11,
  CP-03, CP-04, and CP-07 now support per-column thresholds that override the
  global/dataset threshold for specific columns.

* `compare_snapshots()` — compare any two historical snapshots from the SQLite
  database by ID. Produces a structured list and optional HTML drift report
  without requiring the original files.

* `list_snapshots()` — list available snapshots in the database, optionally
  filtered by dataset name.
```

**cran-comments.md:** Update for 0.2.0 resubmission (after `R CMD check` passes).

---

## Flags and open questions

> **[Q1] RESOLVED:** QC-08 (distinct count) skips `numeric` and `date` forced
> columns — same behaviour as inferred types. Runs for `character` forced columns.

> **[Q2] RESOLVED:** `resolve_col_type()` is exported. Consistent with
> `infer_col_type()` being exported; lets custom check scripts use the effective
> type (respecting overrides) rather than the raw inferred type.

> **[Q3] RESOLVED:** `compare_snapshots()` requires `config_dir`. Both
> `report_output_dir` and thresholds are read from `dqcheckr.yml` in that
> directory — same single source of truth as `run_dq_check()`. The function
> signature becomes:
> `compare_snapshots(dataset_name, snapshot_id_prev = NULL, snapshot_id_curr = NULL,
>   db_path = "data/snapshots.sqlite", config_dir = ".", report = TRUE,
>   open_report = interactive())`

> **[Q4]** The last two lines of `drift02.R` call `list_snapshots()` and
> `run_drift()` unconditionally on source. These are debugging artefacts. The
> package functions have no equivalent — clean by design.

> **[Q5]** SQL injection in `drift02.R`'s `get_snapshots()` and `list_snapshots()`:
> these use `sprintf()` to build SQL. In the package, all queries use DBI
> parameterized binding. **Already addressed in plan — no action needed beyond
> remembering to follow this in implementation.**

> **[Q6] RESOLVED:** HTML report by default; `text_report = TRUE` adds a `.txt`
> file alongside it. The text renderer from the prototype is retained as an
> internal function. Final signature:
> `compare_snapshots(dataset_name, snapshot_id_prev = NULL, snapshot_id_curr = NULL,
>   db_path = "data/snapshots.sqlite", config_dir = ".", report = TRUE,
>   text_report = FALSE, open_report = interactive())`

---

## Estimated change surface

| Area | Files touched | New lines (approx) |
|---|---|---|
| Feature 1 (type override) | utils.R, checks_generic.R, compare.R, snapshot.R | ~80 |
| Feature 2 (col thresholds) | utils.R, checks_generic.R, compare.R | ~40 |
| Feature 3 (drift) | drift.R (new), drift_report.Rmd (new) | ~350 |
| Tests | 3 new test files | ~200 |
| Docs | vignette, roxygen blocks, NEWS, DESCRIPTION | ~150 |
| **Total** | | **~820** |

---

## Implementation order

1. `resolve_col_type()` + `col_threshold()` in utils.R — the foundation everything else depends on
2. Feature 1 check updates (checks_generic.R, compare.R, snapshot.R)
3. Feature 2 threshold updates (checks_generic.R, compare.R)
4. Tests for Features 1 and 2
5. Feature 3: R/drift.R + inst/templates/drift_report.Rmd
6. Tests for Feature 3
7. Vignette updates
8. DESCRIPTION + NEWS.md
9. `devtools::document()` + `devtools::check()`
10. Update cran-comments.md
