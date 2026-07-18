# QC-07: Report numeric summary statistics

For each column whose resolved type is `"numeric"`, returns one `"INFO"`
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
containing min, max, mean, and standard deviation of the parseable
values. Columns inferred as non-numeric are silently skipped.

## Usage

``` r
check_numeric_stats(df, config, types = NULL)
```

## Arguments

- df:

  A data frame with all columns as character vectors (as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

- types:

  Optional named character vector of pre-resolved column types; see
  [`check_inferred_types`](https://mickmioduszewski.github.io/dqcheckr/reference/check_inferred_types.md).

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects (one per numeric column), all with status `"INFO"`. Returns an
empty list if no numeric columns are found.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
check_numeric_stats(df, cfg)
#> [[1]]
#> [[1]]$check_id
#> [1] "QC-07"
#> 
#> [[1]]$check_name
#> [1] "Numeric stats"
#> 
#> [[1]]$column
#> [1] "height"
#> 
#> [[1]]$status
#> [1] "INFO"
#> 
#> [[1]]$observed
#> [1] "min=66, max=264, mean=174.6, sd=34.77"
#> 
#> [[1]]$threshold
#> [1] NA
#> 
#> [[1]]$message
#> [1] "Summary statistics for numeric column 'height'."
#> 
#> 
#> [[2]]
#> [[2]]$check_id
#> [1] "QC-07"
#> 
#> [[2]]$check_name
#> [1] "Numeric stats"
#> 
#> [[2]]$column
#> [1] "mass"
#> 
#> [[2]]$status
#> [1] "INFO"
#> 
#> [[2]]$observed
#> [1] "min=15, max=1358, mean=97.31, sd=169.5"
#> 
#> [[2]]$threshold
#> [1] NA
#> 
#> [[2]]$message
#> [1] "Summary statistics for numeric column 'mass'."
#> 
#> 
#> [[3]]
#> [[3]]$check_id
#> [1] "QC-07"
#> 
#> [[3]]$check_name
#> [1] "Numeric stats"
#> 
#> [[3]]$column
#> [1] "birth_year"
#> 
#> [[3]]$status
#> [1] "INFO"
#> 
#> [[3]]$observed
#> [1] "min=8, max=896, mean=87.57, sd=154.7"
#> 
#> [[3]]$threshold
#> [1] NA
#> 
#> [[3]]$message
#> [1] "Summary statistics for numeric column 'birth_year'."
#> 
#> 
```
