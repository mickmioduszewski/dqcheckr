# Run all version comparison checks between two dataset snapshots

Runs CP-01 to CP-08 comparing a current delivery against the previous
one.

## Usage

``` r
run_comparison_checks(df_current, df_previous, config, con)
```

## Arguments

- df_current:

  Character. DuckDB table name for the current delivery.

- df_previous:

  Character. DuckDB table name for the previous delivery.

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

- con:

  A DuckDB connection from `DBI::dbConnect(duckdb::duckdb())`.

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects. The list carries attributes `new_cols`, `dropped_cols`, and
`type_changed` (character vectors) for use by the snapshot writer.

## Examples

``` r
# \donttest{
cfg_dir   <- system.file("demonstrations/config", package = "dqcheckr")
cfg       <- load_config("starwars_csv", config_dir = cfg_dir)
curr_path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
con       <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
#> Error in (function (cond) .Internal(C_tryCatchHelper(addr, 1L, cond)))(structure(list(message = "there is no package called ‘duckdb’",     call = loadNamespace(x), package = "duckdb", lib.loc = NULL), class = c("packageNotFoundError", "error", "condition"))): error in evaluating the argument 'drv' in selecting a method for function 'dbConnect': there is no package called ‘duckdb’
curr      <- read_dataset(curr_path, cfg, con = con, tbl_name = "curr")
#> Error in read_dataset(curr_path, cfg, con = con, tbl_name = "curr"): unused arguments (cfg, tbl_name = "curr")
prev      <- read_dataset(curr_path, cfg, con = con, tbl_name = "prev")
#> Error in read_dataset(curr_path, cfg, con = con, tbl_name = "prev"): unused arguments (cfg, tbl_name = "prev")
results   <- run_comparison_checks(curr, prev, cfg, con = con)
#> Error in run_comparison_checks(curr, prev, cfg, con = con): unused argument (cfg)
DBI::dbDisconnect(con, shutdown = TRUE)
#> Error in h(simpleError(msg, call)): error in evaluating the argument 'conn' in selecting a method for function 'dbDisconnect': object 'con' not found
# }
```
