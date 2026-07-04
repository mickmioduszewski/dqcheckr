# QC-06: Report inferred column types

Returns one `"INFO"`
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
per column recording the type resolved by
[`resolve_col_type`](https://mickmioduszewski.github.io/dqcheckr/reference/resolve_col_type.md)
(`"date"`, `"numeric"`, `"character"`, or `"unknown"`). Per-column
overrides from `config$column_types` are respected.

## Usage

``` r
check_inferred_types(df, config, types = NULL)
```

## Arguments

- df:

  A data frame with all columns as character vectors (as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

- types:

  Optional named character vector of pre-resolved column types (one
  element per column, as produced by
  [`resolve_col_type`](https://mickmioduszewski.github.io/dqcheckr/reference/resolve_col_type.md)).
  When `NULL` (the default), types are resolved internally. Supplying
  this avoids re-running type inference when several checks share one
  data frame.

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects, one per column, all with status `"INFO"`.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
check_inferred_types(df, cfg)
#> list()
```
