# Run a full data quality check pipeline

Orchestrates the complete dqcheckr pipeline: loads configuration,
detects files, runs QC and comparison checks, writes a snapshot to
SQLite, and renders an HTML report.

## Usage

``` r
run_dq_check(dataset_name, config_dir = ".", open_report = TRUE)
```

## Arguments

- dataset_name:

  Character. Name of the dataset; must match a YAML config file
  `<dataset_name>.yml` in `config_dir`.

- config_dir:

  Character. Path to the directory containing `dqcheckr.yml` and the
  dataset YAML file. Defaults to `"."`.

- open_report:

  Logical. Whether to open the HTML report in the browser after
  rendering (only takes effect in interactive sessions).

## Value

Invisibly, a named list with:

- status:

  Overall status string: `"PASS"`, `"WARN"`, `"FAIL"`, or `"INFO"`.

- report_path:

  Absolute path to the rendered HTML report.

- snapshot_id:

  Integer row ID of the snapshot written to SQLite, or `NULL` if the
  write failed.

## Examples

``` r
if (FALSE) { # \dontrun{
result <- run_dq_check("my_dataset", config_dir = "config")
result$status
} # }
```
