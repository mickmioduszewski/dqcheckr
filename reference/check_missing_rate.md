# QC-01: Check missing rate per column

Returns a
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
per column flagging columns whose proportion of missing or empty values
exceeds `max_missing_rate`.

## Usage

``` r
check_missing_rate(df, config)
```

## Arguments

- df:

  A data frame with all columns as character vectors.

- config:

  Named list as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects, one per column.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
check_missing_rate(df, cfg)
#> list()
```
