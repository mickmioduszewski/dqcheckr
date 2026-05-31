# dqcheckr 0.3.0

## Breaking changes

* **DuckDB replaces SQLite** for snapshot storage. Existing `.sqlite` databases
  must be migrated with `inst/scripts/migrate_sqlite_to_duckdb.R`. Update
  `snapshot_db` in `dqcheckr.yml` to point to the new `.duckdb` path.
* **Quarto replaces rmarkdown** for HTML reports. Install Quarto CLI from
  <https://quarto.org>; the R `quarto` package is now an `Imports` dependency.
* **CP-02 split into three result objects**: `CP-02a` (new columns), `CP-02b`
  (dropped columns), `CP-02c` (type changes). Code that filters on
  `check_id == "CP-02"` must be updated to check `CP-02a`, `CP-02b`, or
  `CP-02c`.
* **`run_timestamp`** is now stored in UTC ISO-8601 format
  (`YYYY-MM-DDTHH:MM:SSZ`). Existing snapshot rows retain the old local-time
  format; new rows use UTC.
* **`numeric_mean`** stat key renamed to **`numeric_parseable_mean`** in
  `column_snapshots`. Existing rows retain the old label; new rows use the new
  label.

## New features

* **DuckDB check-execution**: CSV and Parquet files are registered in an
  in-memory DuckDB connection; all QC and CP checks execute as SQL.
  R-path fallback is preserved for all check functions via `con = NULL`.
* **Parquet input**: add `format: parquet` to the dataset YAML to read
  Parquet files directly via DuckDB.
* **Outlier detection** (`check_outliers()`, check ID `QC-16`): configurable
  Z-score threshold per column via `column_rules.<col>.max_z_score`. Off by
  default (`Inf`).
* **File size check** (`check_file_size()`, check ID `QC-15`): FAIL when
  file exceeds `max_file_size_mb`; always emits an INFO with the actual size.
* **Maximum row count** (`max_row_count`): FAIL when file exceeds configured
  row count (check ID `QC-14b`).
* **Multi-column composite key uniqueness**: `key_columns` now accepts a list
  of column names for composite-key uniqueness checks.
* **PASS rate trend**: `read_pass_rate_trend()` queries the snapshot database
  for per-snapshot PASS rate history.
* **`render_status` column** in `snapshots` table: defaults to `'success'`;
  updated to `'failed'` if the HTML render step fails.
* **`comparison_mode` column** in `snapshots` table: `'single'` for single-file
  runs, `'comparison'` for runs with a previous file.
* **`type_changed_cols_vs_previous` column** in `snapshots` table: stores type
  changes detected by CP-02c.

## Behaviour changes

* `compare_snapshots()` now loads dataset-level `rule_overrides` when a
  dataset YAML exists, so drift `***` markers correctly apply per-dataset
  thresholds.
* `compare_snapshots()` now rejects inverted snapshot IDs
  (`snapshot_id_prev > snapshot_id_curr`) with an error.
* CP-07 now emits a PASS result for columns where the non-numeric rate did not
  increase (previously skipped).
* QC-11 now supports a two-level WARN/FAIL threshold via `warn_non_numeric_rate`
  (default `0.0`, meaning any non-zero non-numeric rate triggers WARN).
* CP-03 (`compare_missing_rate`) severity is now configurable via
  `missing_rate_change_severity` (`"warn"` or `"fail"`; default `"warn"`).
* CP-08 (`compare_column_order`) severity is now configurable via
  `column_order_severity` (`"warn"` or `"fail"`); still defaults to FAIL for
  FWF and WARN for CSV.
* `detect_files()` uses filename alphabetical order as a tiebreaker when
  modification times are equal.
* The `observed` field in QC-09, CP-05, and CP-06 is capped at 20 values to
  avoid oversized output.
* Comparison summary in the HTML report now lists all WARN/FAIL messages as a
  bullet list (previously showed only the single worst message).
* `flag_*` config keys: setting to `false` suppresses the WARN from the report;
  schema changes are always written to the snapshot database regardless.

# dqcheckr 0.2.0

## Bug fixes

* `render_report()` and `.write_drift_html_report()` now pass
  `intermediates_dir = tempdir()` to `rmarkdown::render()`. Previously knitr
  wrote intermediate files (`.knit.md`) to the template directory inside the
  installed package, causing `R CMD check` failures on CRAN Debian builders
  where the user library is remounted read-only during testing.

* `render_report()` now checks `rmarkdown::pandoc_available()` before rendering
  and returns `NULL` invisibly when pandoc is absent, consistent with the
  existing behaviour of the drift report renderer. `run_dq_check()` handles a
  `NULL` report path gracefully and still returns its full result list with
  `report_path = NULL`.

* `list_snapshots()` no longer has a relative-path default for `db_path`. The
  argument is now required; omitting it throws an informative error. The previous
  default `"data/snapshots.sqlite"` could resolve inside the user library
  depending on the working directory at call time.

* Removed runtime output artefacts (`inst/demonstrations/output2/`) that were
  accidentally committed to the package source.

## New features

* **Per-column type overrides** (`column_types` in dataset YAML). Any column can
  be forced to `character`, `numeric`, or `date` regardless of what the data
  looks like. Eliminates false QC-11, CP-02, CP-04, and CP-07 findings on
  columns that are numerically formatted but semantically character (phone
  numbers, postcodes, unit numbers, BSB codes). The new `resolve_col_type()`
  function is exported so custom check scripts can also respect overrides.

* **Per-column threshold overrides** (new keys in `column_rules`). QC-01
  (`max_missing_rate`), QC-11 (`max_non_numeric_rate`), CP-03
  (`max_missing_rate_change_pp`), CP-04 (`max_numeric_mean_shift_pct`), and
  CP-07 (`max_non_numeric_rate_change_pp`) now accept per-column threshold values
  in `column_rules`. Resolution order: per-column > dataset (`rule_overrides`) >
  global (`default_rules`). Existing configs without per-column keys are unchanged.

* **`compare_snapshots()`** compares any two historical snapshots from the
  'SQLite' database by ID, without needing the original files. Produces
  table-level drift, schema drift, and per-column statistical drift. Renders a
  self-contained 'HTML' drift report; a plain-text report is available via
  `text_report = TRUE`. Thresholds and report output directory are read from
  `dqcheckr.yml`.

* **`list_snapshots()`** lists available snapshots in the database, optionally
  filtered by dataset name. Returns a data frame invisibly.

# dqcheckr 0.1.1

* `flag_new_columns`, `flag_dropped_columns`, `flag_type_changes` (in CP-02) and
  `flag_column_order_change` (CP-08) are now honoured. Setting any flag to `false`
  suppresses the corresponding check from the report. Schema changes are still
  tracked in the SQLite snapshot regardless of flags.
* `type_inference_threshold` is now configurable per dataset via `rule_overrides`
  in the dataset YAML (or `default_rules` in the global config). Previously fixed
  at 90%, it now defaults to 90% if not set. Affects QC-06, QC-07, QC-08, QC-11,
  CP-02, CP-04, CP-05, CP-06, and CP-07.

# dqcheckr 0.1.0

Initial release.

* Single-snapshot quality checks: QC-01 to QC-14 (missing rate, empty columns,
  duplicate rows, row/column counts, inferred types, numeric stats, distinct
  counts, allowed values, numeric bounds, non-numeric rate, key uniqueness,
  regex pattern, minimum row count) and SC-01/SC-02 (schema contract).
* Version comparison checks: CP-01 to CP-08 (row count change, schema diff,
  missing rate change, numeric mean shift, new/dropped distinct values,
  non-numeric rate change, column order).
* Custom organisation-specific checks via a plain R file.
* Self-contained HTML report with check tables, historical trend charts, and
  column statistics appendix.
* SQLite snapshot database for long-term trend tracking.
* Supports CSV and fixed-width (FWF) file formats.
* Configuration via global `dqcheckr.yml` and per-dataset YAML files.
