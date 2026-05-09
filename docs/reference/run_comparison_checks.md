# Run all version comparison checks between two dataset snapshots

Runs CP-01 to CP-08 comparing a current delivery against the previous
one.

## Usage

``` r
run_comparison_checks(df_current, df_previous, config)
```

## Arguments

- df_current:

  A data frame. The current delivery.

- df_previous:

  A data frame. The previous delivery.

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects. The list carries attributes `new_cols` and `dropped_cols`
(character vectors) for use by the snapshot writer.

## Examples

``` r
if (FALSE) { # \dontrun{
cfg  <- load_config("my_dataset", "config")
curr <- read_dataset("data/current.csv", cfg)
prev <- read_dataset("data/previous.csv", cfg)
results <- run_comparison_checks(curr, prev, cfg)
} # }
```
