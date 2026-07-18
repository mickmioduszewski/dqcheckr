# SC-01 / SC-02: Check columns against the expected schema contract

Compares the columns present in `df` against `config$expected_columns`:

- **SC-01**: one `"FAIL"` result per column present in the file but not
  listed in `expected_columns`.

- **SC-02**: one `"FAIL"` result per column listed in `expected_columns`
  but absent from the file.

Returns an empty list if `expected_columns` is not configured.

## Usage

``` r
check_schema_contract(df, config)
```

## Arguments

- df:

  A data frame with all columns as character vectors (as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects. Each schema violation produces one `"FAIL"` result; a `"PASS"`
result is emitted for each sub-check when no violations are found.
Returns an empty list if `expected_columns` is not configured.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
check_schema_contract(df, cfg)
#> [[1]]
#> [[1]]$check_id
#> [1] "SC-01"
#> 
#> [[1]]$check_name
#> [1] "Unexpected column"
#> 
#> [[1]]$column
#> [1] NA
#> 
#> [[1]]$status
#> [1] "PASS"
#> 
#> [[1]]$observed
#> [1] "No unexpected columns."
#> 
#> [[1]]$threshold
#> [1] NA
#> 
#> [[1]]$message
#> [1] "All file columns are in the expected schema."
#> 
#> 
#> [[2]]
#> [[2]]$check_id
#> [1] "SC-02"
#> 
#> [[2]]$check_name
#> [1] "Missing expected column"
#> 
#> [[2]]$column
#> [1] NA
#> 
#> [[2]]$status
#> [1] "PASS"
#> 
#> [[2]]$observed
#> [1] "All expected columns are present."
#> 
#> [[2]]$threshold
#> [1] NA
#> 
#> [[2]]$message
#> [1] "No expected columns are missing from the file."
#> 
#> 
```
