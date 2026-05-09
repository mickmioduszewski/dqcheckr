# Run organisation-specific custom checks

Sources the R file specified by `config$custom_checks_file`, which must
define a function `custom_checks(df)` returning a list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects. Returns an empty list if `custom_checks_file` is not set in the
config.

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
if (FALSE) { # \dontrun{
cfg     <- load_config("my_dataset", "config")
df      <- read_dataset("data/current.csv", cfg)
results <- run_custom_checks(df, cfg)
} # }
```
