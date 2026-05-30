# Compare two snapshots from the SQLite database

Reads two historical snapshot records (by ID) from the SQLite database
and computes table-level, schema, and per-column statistical drift.
Optionally renders an HTML drift report and/or a plain-text report.

## Usage

``` r
compare_snapshots(
  dataset_name,
  snapshot_id_prev = NULL,
  snapshot_id_curr = NULL,
  db_path = NULL,
  config_dir = ".",
  report = TRUE,
  text_report = FALSE,
  open_report = interactive()
)
```

## Arguments

- dataset_name:

  Character. Dataset name to compare.

- snapshot_id_prev:

  Integer or `NULL`. ID of the earlier snapshot. If `NULL`, defaults to
  the second-most-recent snapshot by ID.

- snapshot_id_curr:

  Integer or `NULL`. ID of the later snapshot. If `NULL`, defaults to
  the most-recent snapshot by ID.

- db_path:

  Character or `NULL`. Path to the SQLite snapshot database. If `NULL`
  (the default), the path is read from `snapshot_db` in `dqcheckr.yml`.

- config_dir:

  Character. Path to the directory containing `dqcheckr.yml`. Used to
  read thresholds, `report_output_dir`, and (when `db_path` is `NULL`)
  `snapshot_db`.

- report:

  Logical. Whether to render an HTML drift report.

- text_report:

  Logical. Whether to also write a plain-text report alongside the HTML
  report. Defaults to `FALSE`.

- open_report:

  Logical. Whether to open the HTML report in the browser after
  rendering (only takes effect in interactive sessions).

## Value

Invisibly, a named list with elements `dataset_name`, `snap_prev`,
`snap_curr`, `table_drift`, `schema_changes`, `missing_rate_changes`,
`non_numeric_changes`, `mean_shifts`, `distinct_changes`.

## Examples

``` r
# \donttest{
tmp     <- tempdir()
db_path <- file.path(tmp, "snap.sqlite")
cfg_yml <- file.path(tmp, "dqcheckr.yml")
ds_yml  <- file.path(tmp, "starwars_csv.yml")
dat     <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
writeLines(c(
  paste0('snapshot_db: "', db_path, '"'),
  paste0('report_output_dir: "', tmp, '"'),
  'default_rules:',
  '  max_missing_rate: 0.60',
  '  min_row_count: 80'
), cfg_yml)
writeLines(c(
  'dataset_name: "starwars_csv"',
  paste0('current_file: "', dat, '"'),
  'format: csv',
  'encoding: "UTF-8"',
  'delimiter: ","'
), ds_yml)
run_dq_check("starwars_csv", config_dir = tmp, open_report = FALSE)
#> [dqcheckr] starwars_csv: FAIL - 0 warning(s), 2 failure(s). Report: /private/tmp/claude-501/Rtmp9SyEfY/starwars_csv_20260530_125808.html
run_dq_check("starwars_csv", config_dir = tmp, open_report = FALSE)
#> [dqcheckr] starwars_csv: FAIL - 0 warning(s), 2 failure(s). Report: /private/tmp/claude-501/Rtmp9SyEfY/starwars_csv_20260530_125808.html
drift <- compare_snapshots("starwars_csv", config_dir = tmp, report = FALSE)
#> [dqcheckr] drift: starwars_csv snapshot #1 vs #2
names(drift)
#> [1] "dataset_name"         "snap_prev"            "snap_curr"           
#> [4] "table_drift"          "schema_changes"       "missing_rate_changes"
#> [7] "non_numeric_changes"  "mean_shifts"          "distinct_changes"    
# }
```
