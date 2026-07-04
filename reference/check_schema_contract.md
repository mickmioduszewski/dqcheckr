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
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
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
#> [1] "name"
#> 
#> [[2]]$status
#> [1] "FAIL"
#> 
#> [[2]]$observed
#> [1] "Expected column 'name' is absent."
#> 
#> [[2]]$threshold
#> [1] NA
#> 
#> [[2]]$message
#> [1] "Column 'name' is in expected_columns but absent from the file."
#> 
#> 
#> [[3]]
#> [[3]]$check_id
#> [1] "SC-02"
#> 
#> [[3]]$check_name
#> [1] "Missing expected column"
#> 
#> [[3]]$column
#> [1] "height"
#> 
#> [[3]]$status
#> [1] "FAIL"
#> 
#> [[3]]$observed
#> [1] "Expected column 'height' is absent."
#> 
#> [[3]]$threshold
#> [1] NA
#> 
#> [[3]]$message
#> [1] "Column 'height' is in expected_columns but absent from the file."
#> 
#> 
#> [[4]]
#> [[4]]$check_id
#> [1] "SC-02"
#> 
#> [[4]]$check_name
#> [1] "Missing expected column"
#> 
#> [[4]]$column
#> [1] "mass"
#> 
#> [[4]]$status
#> [1] "FAIL"
#> 
#> [[4]]$observed
#> [1] "Expected column 'mass' is absent."
#> 
#> [[4]]$threshold
#> [1] NA
#> 
#> [[4]]$message
#> [1] "Column 'mass' is in expected_columns but absent from the file."
#> 
#> 
#> [[5]]
#> [[5]]$check_id
#> [1] "SC-02"
#> 
#> [[5]]$check_name
#> [1] "Missing expected column"
#> 
#> [[5]]$column
#> [1] "hair_color"
#> 
#> [[5]]$status
#> [1] "FAIL"
#> 
#> [[5]]$observed
#> [1] "Expected column 'hair_color' is absent."
#> 
#> [[5]]$threshold
#> [1] NA
#> 
#> [[5]]$message
#> [1] "Column 'hair_color' is in expected_columns but absent from the file."
#> 
#> 
#> [[6]]
#> [[6]]$check_id
#> [1] "SC-02"
#> 
#> [[6]]$check_name
#> [1] "Missing expected column"
#> 
#> [[6]]$column
#> [1] "skin_color"
#> 
#> [[6]]$status
#> [1] "FAIL"
#> 
#> [[6]]$observed
#> [1] "Expected column 'skin_color' is absent."
#> 
#> [[6]]$threshold
#> [1] NA
#> 
#> [[6]]$message
#> [1] "Column 'skin_color' is in expected_columns but absent from the file."
#> 
#> 
#> [[7]]
#> [[7]]$check_id
#> [1] "SC-02"
#> 
#> [[7]]$check_name
#> [1] "Missing expected column"
#> 
#> [[7]]$column
#> [1] "eye_color"
#> 
#> [[7]]$status
#> [1] "FAIL"
#> 
#> [[7]]$observed
#> [1] "Expected column 'eye_color' is absent."
#> 
#> [[7]]$threshold
#> [1] NA
#> 
#> [[7]]$message
#> [1] "Column 'eye_color' is in expected_columns but absent from the file."
#> 
#> 
#> [[8]]
#> [[8]]$check_id
#> [1] "SC-02"
#> 
#> [[8]]$check_name
#> [1] "Missing expected column"
#> 
#> [[8]]$column
#> [1] "birth_year"
#> 
#> [[8]]$status
#> [1] "FAIL"
#> 
#> [[8]]$observed
#> [1] "Expected column 'birth_year' is absent."
#> 
#> [[8]]$threshold
#> [1] NA
#> 
#> [[8]]$message
#> [1] "Column 'birth_year' is in expected_columns but absent from the file."
#> 
#> 
#> [[9]]
#> [[9]]$check_id
#> [1] "SC-02"
#> 
#> [[9]]$check_name
#> [1] "Missing expected column"
#> 
#> [[9]]$column
#> [1] "sex"
#> 
#> [[9]]$status
#> [1] "FAIL"
#> 
#> [[9]]$observed
#> [1] "Expected column 'sex' is absent."
#> 
#> [[9]]$threshold
#> [1] NA
#> 
#> [[9]]$message
#> [1] "Column 'sex' is in expected_columns but absent from the file."
#> 
#> 
#> [[10]]
#> [[10]]$check_id
#> [1] "SC-02"
#> 
#> [[10]]$check_name
#> [1] "Missing expected column"
#> 
#> [[10]]$column
#> [1] "gender"
#> 
#> [[10]]$status
#> [1] "FAIL"
#> 
#> [[10]]$observed
#> [1] "Expected column 'gender' is absent."
#> 
#> [[10]]$threshold
#> [1] NA
#> 
#> [[10]]$message
#> [1] "Column 'gender' is in expected_columns but absent from the file."
#> 
#> 
#> [[11]]
#> [[11]]$check_id
#> [1] "SC-02"
#> 
#> [[11]]$check_name
#> [1] "Missing expected column"
#> 
#> [[11]]$column
#> [1] "homeworld"
#> 
#> [[11]]$status
#> [1] "FAIL"
#> 
#> [[11]]$observed
#> [1] "Expected column 'homeworld' is absent."
#> 
#> [[11]]$threshold
#> [1] NA
#> 
#> [[11]]$message
#> [1] "Column 'homeworld' is in expected_columns but absent from the file."
#> 
#> 
#> [[12]]
#> [[12]]$check_id
#> [1] "SC-02"
#> 
#> [[12]]$check_name
#> [1] "Missing expected column"
#> 
#> [[12]]$column
#> [1] "species"
#> 
#> [[12]]$status
#> [1] "FAIL"
#> 
#> [[12]]$observed
#> [1] "Expected column 'species' is absent."
#> 
#> [[12]]$threshold
#> [1] NA
#> 
#> [[12]]$message
#> [1] "Column 'species' is in expected_columns but absent from the file."
#> 
#> 
#> [[13]]
#> [[13]]$check_id
#> [1] "SC-02"
#> 
#> [[13]]$check_name
#> [1] "Missing expected column"
#> 
#> [[13]]$column
#> [1] "films"
#> 
#> [[13]]$status
#> [1] "FAIL"
#> 
#> [[13]]$observed
#> [1] "Expected column 'films' is absent."
#> 
#> [[13]]$threshold
#> [1] NA
#> 
#> [[13]]$message
#> [1] "Column 'films' is in expected_columns but absent from the file."
#> 
#> 
#> [[14]]
#> [[14]]$check_id
#> [1] "SC-02"
#> 
#> [[14]]$check_name
#> [1] "Missing expected column"
#> 
#> [[14]]$column
#> [1] "vehicles"
#> 
#> [[14]]$status
#> [1] "FAIL"
#> 
#> [[14]]$observed
#> [1] "Expected column 'vehicles' is absent."
#> 
#> [[14]]$threshold
#> [1] NA
#> 
#> [[14]]$message
#> [1] "Column 'vehicles' is in expected_columns but absent from the file."
#> 
#> 
#> [[15]]
#> [[15]]$check_id
#> [1] "SC-02"
#> 
#> [[15]]$check_name
#> [1] "Missing expected column"
#> 
#> [[15]]$column
#> [1] "starships"
#> 
#> [[15]]$status
#> [1] "FAIL"
#> 
#> [[15]]$observed
#> [1] "Expected column 'starships' is absent."
#> 
#> [[15]]$threshold
#> [1] NA
#> 
#> [[15]]$message
#> [1] "Column 'starships' is in expected_columns but absent from the file."
#> 
#> 
```
