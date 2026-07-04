# Package index

## Run a quality check

The top-level pipeline and the check-suite runners it orchestrates.

- [`run_dq_check()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_dq_check.md)
  : Run a full data quality check pipeline
- [`run_qc_checks()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_qc_checks.md)
  : Run all generic quality checks on a dataset
- [`run_comparison_checks()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_comparison_checks.md)
  : Run all version comparison checks between two dataset snapshots
- [`run_custom_checks()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_custom_checks.md)
  : Run organisation-specific custom checks

## Individual checks

The QC and schema checks run by
[`run_qc_checks()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_qc_checks.md).

- [`check_allowed_values()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_allowed_values.md)
  : QC-09: Check for values outside the allowed set
- [`check_col_count()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_col_count.md)
  : QC-05: Report column count
- [`check_distinct_counts()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_distinct_counts.md)
  : QC-08: Report distinct value counts for character columns
- [`check_duplicate_rows()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_duplicate_rows.md)
  : QC-03: Check for fully-duplicate rows
- [`check_empty_column()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_empty_column.md)
  : QC-02: Check for entirely empty columns
- [`check_inferred_types()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_inferred_types.md)
  : QC-06: Report inferred column types
- [`check_key_uniqueness()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_key_uniqueness.md)
  : QC-12: Check uniqueness of key column(s)
- [`check_min_row_count()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_min_row_count.md)
  : QC-14: Check row count bounds and optional file size
- [`check_missing_rate()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_missing_rate.md)
  : QC-01: Check missing rate per column
- [`check_non_numeric()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_non_numeric.md)
  : QC-11: Check non-numeric rate in numeric columns
- [`check_numeric_bounds()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_numeric_bounds.md)
  : QC-10: Check for out-of-range numeric values
- [`check_numeric_stats()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_numeric_stats.md)
  : QC-07: Report numeric summary statistics
- [`check_outliers()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_outliers.md)
  : QC-15: Detect statistical outliers in numeric columns
- [`check_pattern()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_pattern.md)
  : QC-13: Check values against a regex pattern
- [`check_row_count()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_row_count.md)
  : QC-04: Report row count
- [`check_schema_contract()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_schema_contract.md)
  : SC-01 / SC-02: Check columns against the expected schema contract

## Snapshots and drift

The SQLite snapshot history and cross-run drift comparison.

- [`compare_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/compare_snapshots.md)
  : Compare two snapshots from the SQLite database
- [`list_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/list_snapshots.md)
  : List snapshots available in the database
- [`read_recent_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/read_recent_snapshots.md)
  : Read recent snapshot history from the SQLite database

## Configuration and ingest

- [`load_config()`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md)
  : Load and merge dataset configuration
- [`detect_files()`](https://mickmioduszewski.github.io/dqcheckr/reference/detect_files.md)
  : Detect current and previous dataset files
- [`read_dataset()`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)
  : Read a dataset file into a data frame

## Building blocks

Helpers for writing custom checks and interpreting results.

- [`dq_result()`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
  : Construct a data quality result object
- [`overall_status()`](https://mickmioduszewski.github.io/dqcheckr/reference/overall_status.md)
  : Compute the worst status across a list of dq_result objects
- [`infer_col_type()`](https://mickmioduszewski.github.io/dqcheckr/reference/infer_col_type.md)
  : Infer the logical type of a character column
- [`resolve_col_type()`](https://mickmioduszewski.github.io/dqcheckr/reference/resolve_col_type.md)
  : Resolve the effective type of a column, respecting config overrides
