# QC-08: Report distinct value counts for character columns

For each column whose resolved type is `"character"`, returns one
`"INFO"`
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
with the count of distinct non-empty values. Columns inferred as numeric
or date are silently skipped.

## Usage

``` r
check_distinct_counts(df, config, types = NULL)
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
objects (one per character column), all with status `"INFO"`. Returns an
empty list if no character columns are found.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
check_distinct_counts(df, cfg)
#> list()
```
