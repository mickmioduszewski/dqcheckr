# dqcheckr 0.2.0 (development)

* Snapshot storage upgraded from RSQLite to DuckDB (Change 1 / impact01).
* Reports migrated from rmarkdown to Quarto (Change 3 / impact01).
* New `compare_snapshots()` and `list_snapshots()` functions for drift analysis.
* New `drift_report.qmd` template; `render_drift_report()` added to `R/drift.R`.
* `detect_files()` now uses filename as a tiebreaker when two files share the
  same modification time, making folder-mode ordering deterministic (RC-01).
* `compare_non_numeric_rate()` (CP-07) now emits a PASS result for columns
  where the rate does not increase, consistent with all other CP checks (G-02).
* `check_min_row_count()` and `check_row_count()` now route through a new
  `table_threshold()` helper, consistent with `col_threshold()` (G-07).
* `snapshots` table gains a `comparison_mode` column (`'comparison'` or
  `'single'`) so single-file runs are distinguishable from no-change comparison
  runs in historical queries (G-04).
* `snapshots` table gains a `render_status` column (`'success'` or `'failed'`)
  so orphaned snapshots from a failed render are identifiable (RC-02 / option c).
* `compare_snapshots()` now uses the full merged per-dataset config for threshold
  comparisons, so `***` markers in drift reports match the original check run for
  datasets with rule overrides (G-05 / G-06).
* `compute_col_stats()` unused `qc_results` parameter removed (D-01).
* `run_timestamp` is now stored in UTC (RC-07).
* `check_allowed_values()` (QC-09) and `compare_new_values()` / `compare_dropped_values()`
  (CP-05, CP-06) cap `observed` at 20 values with an `"... and N more"` suffix (RC-04, RC-05).

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
