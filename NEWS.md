# dqcheckr 0.2.0

## New features

* New `compare_snapshots()` and `list_snapshots()` functions for drift analysis.
  Compares any two historical snapshots and optionally renders an HTML drift
  report with per-column statistical drift, schema changes, and trend charts.
* New `resolve_col_type()` function: returns the effective type for a column,
  respecting per-column type overrides set in the `column_types` config key.
* New `QC-15` outlier detection check (`check_outliers()`). Configured via
  `max_z_score` and/or `iqr_fence_multiplier`; skipped silently when neither is
  set.
* `check_key_uniqueness()` (QC-12) now supports composite keys: set
  `key_columns` to a character vector in the dataset YAML.
* `check_min_row_count()` (QC-14) gains `max_row_count` and `max_file_size_mb`
  thresholds.
* `col_threshold()` and `table_threshold()` added as internal helpers;
  `column_rules` per-column threshold overrides are now correctly stored in
  `column_snapshots.threshold` (G-01).

## Behaviour changes

* Reports migrated from rmarkdown to Quarto. `render_report()` uses
  `quarto::quarto_render()` and returns `NULL` with a warning when Quarto CLI
  is not installed.
* `compare_schema()` (CP-02) split into three separate result objects:
  CP-02a (new columns), CP-02b (dropped columns), CP-02c (type changes).
* `compare_non_numeric_rate()` (CP-07) now always emits a result for every
  eligible column, including PASS for columns where the rate did not increase
  (G-02).
* `run_timestamp` is now stored in ISO-8601 UTC format
  (`2026-01-01T12:00:00Z`) rather than local time (RC-07).
* `snapshots` table gains three columns on first use: `comparison_mode`,
  `render_status`, and `type_changed_cols_vs_previous`. Existing 0.1.x
  databases are auto-migrated on the first 0.2.0 run.
* SQLite foreign key enforcement is now explicitly enabled on every connection
  (`PRAGMA foreign_keys = ON`).
* `detect_files()` uses filename as a secondary sort when two files share the
  same modification time, making folder-mode ordering deterministic (RC-01).
* `check_allowed_values()` (QC-09), `compare_new_values()` (CP-05), and
  `compare_dropped_values()` (CP-06) cap `observed` at 20 values with an
  `"... and N more"` suffix (RC-04, RC-05).
* `check_non_numeric()` (QC-11) gains a `warn_non_numeric_rate` config key for
  a separate WARN threshold (C-01).
* `compare_missing_rate()` (CP-03) gains a `missing_rate_change_severity`
  config key (`warn` / `fail`) (B-07).
* `compare_column_order()` (CP-08) gains a `column_order_severity` config key
  that overrides the format-based default (C-02).
* `compute_col_stats()` stores the numeric mean under the key
  `numeric_parseable_mean` (renamed from `numeric_mean`) to clarify that
  non-parseable values are excluded from the calculation (C-04).
* Comparison summary in the HTML report now lists all FAIL/WARN messages as a
  bullet list rather than picking the single worst result (C-05).
* `compare_snapshots()` uses the full merged per-dataset config for drift
  threshold comparisons, so `***` markers match the original check run for
  datasets with `rule_overrides` (G-05/G-06).
* `compute_col_stats()` unused `qc_results` parameter removed (D-01).

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
