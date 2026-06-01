# Run organisation-specific custom checks

Sources the R file specified by `config$custom_checks_file`, which must
define a function `custom_checks(df)` or `custom_checks(df, config)`
returning a list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects. If the function accepts a second argument the merged config is
passed, giving access to
[`resolve_col_type`](https://mickmioduszewski.github.io/dqcheckr/reference/resolve_col_type.md)
and column rules. Returns an empty list if `custom_checks_file` is not
set in the config.

## Usage

``` r
run_custom_checks(df, config)
```

## Arguments

- df:

  A data frame. The current delivery.

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects (may be empty).

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg     <- load_config("starwars_csv", config_dir = cfg_dir)
df      <- data.frame(name = c("Luke", "Leia"), stringsAsFactors = FALSE)
results <- run_custom_checks(df, cfg)
```
