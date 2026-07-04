# Resolve the effective type of a column, respecting config overrides

Returns the type for `col` from the `column_types` map in `config` if
one is set, otherwise falls back to
[`infer_col_type`](https://mickmioduszewski.github.io/dqcheckr/reference/infer_col_type.md).
Use this in custom check scripts instead of calling
[`infer_col_type()`](https://mickmioduszewski.github.io/dqcheckr/reference/infer_col_type.md)
directly so that type overrides are respected.

## Usage

``` r
resolve_col_type(col, x, config)
```

## Arguments

- col:

  Character. Column name.

- x:

  Character vector. The column's values (as read from the file).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

## Value

A single character string: `"date"`, `"numeric"`, `"character"`, or
`"unknown"`.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg <- load_config("starwars_csv", config_dir = cfg_dir)
resolve_col_type("name", c("Luke", "Leia", "Han"), cfg)   # "character"
#> [1] "character"
```
