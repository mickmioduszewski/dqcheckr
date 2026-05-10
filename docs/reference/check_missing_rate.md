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
if (FALSE) { # \dontrun{
cfg <- load_config("my_dataset", "config")
df  <- read_dataset("data/file.csv", cfg)
check_missing_rate(df, cfg)
} # }
```
