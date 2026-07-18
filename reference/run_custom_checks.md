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

## Details

The file is sourced into an isolated environment whose parent is
[`baseenv()`](https://rdrr.io/r/base/environment.html), so only base R
functions are available by default.
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
is explicitly injected and can be called without qualification. All
other dqcheckr exports (e.g. `resolve_col_type`, `infer_col_type`) must
be qualified:
[`dqcheckr::resolve_col_type()`](https://mickmioduszewski.github.io/dqcheckr/reference/resolve_col_type.md).
Any error – missing file, undefined function, runtime failure, or a
malformed result element (each element must have the seven
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
fields and a valid status) – stops the run with a clear message.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg     <- load_config("starwars_csv", config_dir = cfg_dir)
path    <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df      <- read_dataset(path, cfg)
results <- run_custom_checks(df, cfg)
```
