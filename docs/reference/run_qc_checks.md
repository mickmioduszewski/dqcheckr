# Run all generic quality checks on a dataset

Runs the full QC check suite (QC-01 to QC-16, SC-01, SC-02) against a
single dataset snapshot.

## Usage

``` r
run_qc_checks(df, config, file_path = NULL, con)
```

## Arguments

- df:

  Character. DuckDB table name as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

- file_path:

  Character. Path to the source file; used for the `max_file_size_mb`
  check. Pass `NULL` to skip the size check.

- con:

  A DuckDB connection from `DBI::dbConnect(duckdb::duckdb())`.

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects.

## Examples

``` r
# \donttest{
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg     <- load_config("starwars_csv", config_dir = cfg_dir)
path    <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
con     <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
#> Error in (function (cond) .Internal(C_tryCatchHelper(addr, 1L, cond)))(structure(list(message = "there is no package called ‘duckdb’",     call = loadNamespace(x), package = "duckdb", lib.loc = NULL), class = c("packageNotFoundError", "error", "condition"))): error in evaluating the argument 'drv' in selecting a method for function 'dbConnect': there is no package called ‘duckdb’
tbl     <- read_dataset(path, cfg, con = con)
#> Error in read_dataset(path, cfg, con = con): unused argument (cfg)
results <- run_qc_checks(tbl, cfg, file_path = path, con = con)
#> Error in run_qc_checks(tbl, cfg, file_path = path, con = con): unused argument (cfg)
DBI::dbDisconnect(con, shutdown = TRUE)
#> Error in h(simpleError(msg, call)): error in evaluating the argument 'conn' in selecting a method for function 'dbDisconnect': object 'con' not found
# }
```
