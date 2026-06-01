# Package index

## Run checks

Main entry point and individual check runners

- [`run_dq_check()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_dq_check.md)
  : Run a full data quality check pipeline
- [`run_qc_checks()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_qc_checks.md)
  : Run all generic quality checks on a dataset
- [`run_comparison_checks()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_comparison_checks.md)
  : Run all version comparison checks between two dataset snapshots
- [`run_custom_checks()`](https://mickmioduszewski.github.io/dqcheckr/reference/run_custom_checks.md)
  : Run organisation-specific custom checks

## Configuration & ingestion

Load config and read dataset files

- [`load_config()`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md)
  : Load and merge dataset configuration
- [`detect_files()`](https://mickmioduszewski.github.io/dqcheckr/reference/detect_files.md)
  : Detect current and previous dataset files
- [`read_dataset()`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)
  : Read a dataset file into a DuckDB table

## Results

Construct and interpret result objects

- [`dq_result()`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
  : Construct a data quality result object
- [`overall_status()`](https://mickmioduszewski.github.io/dqcheckr/reference/overall_status.md)
  : Compute the worst status across a list of dq_result objects
- [`infer_col_type()`](https://mickmioduszewski.github.io/dqcheckr/reference/infer_col_type.md)
  : Infer the logical type of a character column
- [`resolve_col_type()`](https://mickmioduszewski.github.io/dqcheckr/reference/resolve_col_type.md)
  : Resolve the effective type of a column, respecting config overrides
- [`check_missing_rate()`](https://mickmioduszewski.github.io/dqcheckr/reference/check_missing_rate.md)
  : QC-01: Check missing rate per column

## Snapshot database & drift analysis

Query snapshot history and compare snapshots over time

- [`read_recent_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/read_recent_snapshots.md)
  : Read recent snapshot history from the DuckDB database
- [`list_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/list_snapshots.md)
  : List snapshots available in the database
- [`compare_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/compare_snapshots.md)
  : Compare two snapshots from the DuckDB database

## Helpers

Utility functions

- [`col_threshold()`](https://mickmioduszewski.github.io/dqcheckr/reference/col_threshold.md)
  : Look up the effective threshold for a check, with per-column
  fallback
