# Run all generic quality checks on a dataset

Runs the full QC check suite (QC-01 to QC-15, SC-01, SC-02) against a
single data frame snapshot.

## Usage

``` r
run_qc_checks(df, config, file_path = NULL, types = NULL)
```

## Arguments

- df:

  A data frame with all columns as character vectors (as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

- file_path:

  Character or `NULL`. Absolute path to the file, used for the optional
  `max_file_size_mb` check in QC-14.

- types:

  Optional named character vector of pre-resolved column types; see
  [`check_inferred_types`](https://mickmioduszewski.github.io/dqcheckr/reference/check_inferred_types.md).
  When `NULL` (the default), types are resolved once here and shared by
  all type-dependent checks.

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg     <- load_config("starwars_csv", config_dir = cfg_dir)
path    <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df      <- read_dataset(path, cfg)
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
results <- run_qc_checks(df, cfg)
#> Error in duplicated.default(df): duplicated() applies only to vectors
```
