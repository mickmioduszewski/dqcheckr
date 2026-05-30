# Read recent snapshot history from the SQLite database

Retrieves the `n` most recent run records for a given dataset from the
snapshot database, ordered newest-first.

## Usage

``` r
read_recent_snapshots(db_path, dataset_name, n = 10)
```

## Arguments

- db_path:

  Character. Path to the SQLite database file.

- dataset_name:

  Character. Dataset name to filter on.

- n:

  Integer. Maximum number of records to return. Defaults to 10.

## Value

A data frame with one row per run and columns including `id`,
`run_timestamp`, `file_name`, `row_count`, `overall_status`,
`check_pass_count`, `check_warn_count`, `check_fail_count`. Returns an
empty data frame if the database does not exist or contains no records
for the dataset.

## Examples

``` r
history <- read_recent_snapshots(tempfile(fileext = ".sqlite"), "starwars_csv")
```
