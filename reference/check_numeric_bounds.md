# QC-10: Check for out-of-range numeric values

For each column that has `min_value` or `max_value` configured in
`config$column_rules`, returns a
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
flagging any values that fall outside the specified range. Returns an
empty list when no bound rules are configured.

## Usage

``` r
check_numeric_bounds(df, config)
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
objects, one per configured column. Status is `"FAIL"` when out-of-range
values are found; `"PASS"` otherwise. Returns an empty list if no bound
rules are configured.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
check_numeric_bounds(df, cfg)
#> [[1]]
#> [[1]]$check_id
#> [1] "QC-10"
#> 
#> [[1]]$check_name
#> [1] "Numeric bounds"
#> 
#> [[1]]$column
#> [1] "height"
#> 
#> [[1]]$status
#> [1] "PASS"
#> 
#> [[1]]$observed
#> [1] "All values are within bounds."
#> 
#> [[1]]$threshold
#> [1] "min: 50; max: 300"
#> 
#> [[1]]$message
#> [1] "Column 'height' values are all within bounds."
#> 
#> 
#> [[2]]
#> [[2]]$check_id
#> [1] "QC-10"
#> 
#> [[2]]$check_name
#> [1] "Numeric bounds"
#> 
#> [[2]]$column
#> [1] "mass"
#> 
#> [[2]]$status
#> [1] "PASS"
#> 
#> [[2]]$observed
#> [1] "All values are within bounds."
#> 
#> [[2]]$threshold
#> [1] "min: 1; max: 2000"
#> 
#> [[2]]$message
#> [1] "Column 'mass' values are all within bounds."
#> 
#> 
```
