# QC-09: Check for values outside the allowed set

For each column that has `allowed_values` configured in
`config$column_rules`, returns a
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
flagging any non-empty values not in the allowed list. Returns an empty
list when no `allowed_values` rules are configured.

## Usage

``` r
check_allowed_values(df, config)
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
objects, one per configured column. Status is `"FAIL"` when unexpected
values are found; `"PASS"` otherwise. Returns an empty list if no
`allowed_values` rules are configured.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
check_allowed_values(df, cfg)
#> list()
```
