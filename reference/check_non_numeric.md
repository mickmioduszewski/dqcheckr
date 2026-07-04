# QC-11: Check non-numeric rate in numeric columns

For each column whose resolved type is `"numeric"`, computes the
proportion of non-empty values that cannot be coerced to numeric.
Returns `"FAIL"` when the rate exceeds `max_non_numeric_rate` (default
0.01), `"WARN"` when it exceeds `warn_non_numeric_rate` (default 0), and
`"PASS"` otherwise. Both thresholds support per-column overrides via
`config$column_rules`.

## Usage

``` r
check_non_numeric(df, config, types = NULL)
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
objects, one per numeric column. Returns an empty list if no numeric
columns are found.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
check_non_numeric(df, cfg)
#> list()
```
