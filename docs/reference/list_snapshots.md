# List snapshots available in the database

Returns a data frame of snapshot records for the given dataset (or all
datasets if `dataset_name` is `NULL`), ordered by dataset name and
snapshot ID.

## Usage

``` r
list_snapshots(dataset_name = NULL, db_path = "data/snapshots.sqlite")
```

## Arguments

- dataset_name:

  Character or `NULL`. If supplied, only snapshots for that dataset are
  returned. If `NULL`, all datasets are returned.

- db_path:

  Character. Path to the SQLite snapshot database.

## Value

A data frame with columns `id`, `dataset_name`, `file_name`,
`run_timestamp`, `row_count`, `overall_status`. Returns an empty data
frame if the database does not exist or contains no matching records.

## Examples

``` r
list_snapshots(db_path = tempfile(fileext = ".sqlite"))
```
