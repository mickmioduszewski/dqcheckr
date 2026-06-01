# QC-01: Check missing rate per column

Returns a
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
per column flagging columns whose proportion of missing or empty values
exceeds `max_missing_rate`.

## Usage

``` r
check_missing_rate(df, config, con)
```

## Arguments

- df:

  Character. DuckDB table name as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md).

- config:

  Named list as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

- con:

  A DuckDB connection from `DBI::dbConnect(duckdb::duckdb())`.

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects, one per column.

## Examples

``` r
# \donttest{
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
con  <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
#> Error in (function (cond) .Internal(C_tryCatchHelper(addr, 1L, cond)))(structure(list(message = "there is no package called ‘duckdb’",     call = loadNamespace(x), package = "duckdb", lib.loc = NULL), class = c("packageNotFoundError", "error", "condition"))): error in evaluating the argument 'drv' in selecting a method for function 'dbConnect': there is no package called ‘duckdb’
tbl  <- read_dataset(path, cfg, con = con)
#> Error in read_dataset(path, cfg, con = con): unused argument (cfg)
check_missing_rate(tbl, cfg, con = con)
#> Error in check_missing_rate(tbl, cfg, con = con): unused argument (cfg)
DBI::dbDisconnect(con, shutdown = TRUE)
#> Error in h(simpleError(msg, call)): error in evaluating the argument 'conn' in selecting a method for function 'dbDisconnect': object 'con' not found
# }
```
