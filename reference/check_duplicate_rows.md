# QC-03: Check for fully-duplicate rows

Returns a single
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
for the whole table. A row is considered a duplicate when every column
value is identical to another row.

## Usage

``` r
check_duplicate_rows(df, config)
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
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md).
Status is `"WARN"` if any duplicate rows exist; `"PASS"` otherwise.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
check_duplicate_rows(df, cfg)
#> Error in duplicated.default(df): duplicated() applies only to vectors
```
