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
  : Read a dataset file into a data frame

## Results

Construct and interpret result objects

- [`dq_result()`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
  : Construct a data quality result object

## Snapshot database

Query the SQLite snapshot history

- [`read_recent_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/read_recent_snapshots.md)
  : Read recent snapshot history from the SQLite database

## Internals

Internal functions (not for direct use)

- [`infer_col_type()`](https://mickmioduszewski.github.io/dqcheckr/reference/infer_col_type.md)
  : Infer the logical type of a character column
- [`overall_status()`](https://mickmioduszewski.github.io/dqcheckr/reference/overall_status.md)
  : Compute the worst status across a list of dq_result objects
- [`compute_col_stats()`](https://mickmioduszewski.github.io/dqcheckr/reference/compute_col_stats.md)
  : Compute per-column statistics for snapshot storage
- [`init_snapshot_db()`](https://mickmioduszewski.github.io/dqcheckr/reference/init_snapshot_db.md)
  : Initialise the SQLite snapshot database
- [`write_snapshot()`](https://mickmioduszewski.github.io/dqcheckr/reference/write_snapshot.md)
  : Write a run snapshot to the SQLite database
- [`render_report()`](https://mickmioduszewski.github.io/dqcheckr/reference/render_report.md)
  : Render the HTML data quality report
