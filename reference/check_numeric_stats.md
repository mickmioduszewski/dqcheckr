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
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
check_numeric_stats(df, cfg)
#> list()
```
