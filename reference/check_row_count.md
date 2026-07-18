# QC-04: Report row count

Returns a single `"INFO"`
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
recording the number of rows in the data frame. Never fails or warns;
use
[`check_min_row_count`](https://mickmioduszewski.github.io/dqcheckr/reference/check_min_row_count.md)
for threshold-based row count checks.

## Usage

``` r
check_row_count(df, config)
```

## Arguments

- df:

  A data frame with all columns as character vectors (as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).
  Currently unused; present for API consistency.

## Value

A list containing one
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
with status `"INFO"`.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
check_row_count(df, cfg)
#> [[1]]
#> [[1]]$check_id
#> [1] "QC-04"
#> 
#> [[1]]$check_name
#> [1] "Row count"
#> 
#> [[1]]$column
#> [1] NA
#> 
#> [[1]]$status
#> [1] "INFO"
#> 
#> [[1]]$observed
#> [1] "87"
#> 
#> [[1]]$threshold
#> [1] NA
#> 
#> [[1]]$message
#> [1] "File contains 87 rows."
#> 
#> 
```
