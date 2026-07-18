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

  Absolute path to the rendered HTML report, or `NULL` if rendering was
  skipped.

- snapshot_id:

  Integer row ID of the snapshot written to SQLite, or `NULL` if the
  write failed.

## Note

Relative `snapshot_db` and `report_output_dir` config values resolve
against the R process's *working directory*, not against `config_dir`.
Run from the deployment root (the directory containing `config/`,
`data/`, `reports/`) or use absolute paths in the config; otherwise a
fresh snapshot database is silently created wherever the process happens
to be running.

## Examples

``` r
# \donttest{
tmp <- gsub("\\\\", "/", tempdir())
dat <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
writeLines(c(
  paste0('snapshot_db: "',       tmp, '/snap.sqlite"'),
  paste0('report_output_dir: "', tmp, '"'),
  'default_rules:',
  '  max_missing_rate: 0.60',
  '  min_row_count: 80'
), file.path(tmp, "dqcheckr.yml"))
writeLines(c(
  'dataset_name: "starwars_csv"',
  paste0('current_file: "', dat, '"'),
  'format: csv',
  'encoding: "UTF-8"',
  'delimiter: ","'
), file.path(tmp, "starwars_csv.yml"))
result <- run_dq_check("starwars_csv", config_dir = tmp, open_report = FALSE)
#> [dqcheckr] starwars_csv: FAIL - 0 warning(s), 2 failure(s). Report: /tmp/RtmpZlIN7w/starwars_csv_20260718_005326_3.html
result$status
#> [1] "FAIL"
# }
```
