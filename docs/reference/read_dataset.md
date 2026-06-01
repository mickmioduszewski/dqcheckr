# Read a dataset file into a DuckDB table

Reads a CSV, fixed-width, or Parquet file directly into an in-memory
DuckDB table. All columns are stored as `VARCHAR`. CSV and FWF values
are whitespace-trimmed. The name of the created table is returned as a
`character(1)`.

## Usage

``` r
read_dataset(path, config, con = NULL, tbl_name = "current_data")
```

## Arguments

- path:

  Character. Path to the file to read.

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).
  Must include `format` (`"csv"`, `"fwf"`, or `"parquet"`). For FWF
  files, `fwf_widths` is required and `fwf_col_names` and `fwf_skip` are
  optional.

- con:

  A DuckDB connection from `DBI::dbConnect(duckdb::duckdb())`. Required
  — the function aborts if `NULL`.

- tbl_name:

  Character. Name to use for the DuckDB table. Defaults to
  `"current_data"`.

## Value

The value of `tbl_name` (a character table name in the DuckDB
connection).

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
DBI::dbGetQuery(con, paste("SELECT * FROM", tbl, "LIMIT 5"))
#> Error in h(simpleError(msg, call)): error in evaluating the argument 'conn' in selecting a method for function 'dbGetQuery': object 'con' not found
DBI::dbDisconnect(con, shutdown = TRUE)
#> Error in h(simpleError(msg, call)): error in evaluating the argument 'conn' in selecting a method for function 'dbDisconnect': object 'con' not found
# }
```
