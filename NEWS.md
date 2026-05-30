# dqcheckr 0.2.0

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
