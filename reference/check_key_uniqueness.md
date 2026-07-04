# QC-12: Check uniqueness of key column(s)

Checks that the column(s) listed in `config$key_columns` have no
duplicate values. When `key_columns` is a single string, one result is
returned for that column. When it is a character vector of length \> 1,
a single result covering the composite key is returned. Returns an empty
list if `key_columns` is not configured.

## Usage

``` r
check_key_uniqueness(df, config)
```

## Arguments

- df:

  A data frame with all columns as character vectors (as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects. Status is `"FAIL"` when duplicates or missing key columns are
detected; `"PASS"` otherwise. Returns an empty list if `key_columns` is
not configured.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
check_key_uniqueness(df, cfg)
#> [[1]]
#> [[1]]$check_id
#> [1] "QC-12"
#> 
#> [[1]]$check_name
#> [1] "Key uniqueness"
#> 
#> [[1]]$column
#> [1] "name"
#> 
#> [[1]]$status
#> [1] "FAIL"
#> 
#> [[1]]$observed
#> [1] "Column not found in file"
#> 
#> [[1]]$threshold
#> [1] NA
#> 
#> [[1]]$message
#> [1] "Key column 'name' is not present in the file."
#> 
#> 
```
