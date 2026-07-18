# QC-02: Check for entirely empty columns

Returns a
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
per column. A column is considered empty when every value is `NA` or the
empty string `""`.

## Usage

``` r
check_empty_column(df, config)
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
objects, one per column. Status is `"FAIL"` for entirely empty columns;
`"PASS"` otherwise.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
check_empty_column(df, cfg)
#> [[1]]
#> [[1]]$check_id
#> [1] "QC-02"
#> 
#> [[1]]$check_name
#> [1] "Empty column"
#> 
#> [[1]]$column
#> [1] "name"
#> 
#> [[1]]$status
#> [1] "PASS"
#> 
#> [[1]]$observed
#> [1] "Not empty"
#> 
#> [[1]]$threshold
#> [1] NA
#> 
#> [[1]]$message
#> [1] "Column 'name' has at least one non-empty value."
#> 
#> 
#> [[2]]
#> [[2]]$check_id
#> [1] "QC-02"
#> 
#> [[2]]$check_name
#> [1] "Empty column"
#> 
#> [[2]]$column
#> [1] "height"
#> 
#> [[2]]$status
#> [1] "PASS"
#> 
#> [[2]]$observed
#> [1] "Not empty"
#> 
#> [[2]]$threshold
#> [1] NA
#> 
#> [[2]]$message
#> [1] "Column 'height' has at least one non-empty value."
#> 
#> 
#> [[3]]
#> [[3]]$check_id
#> [1] "QC-02"
#> 
#> [[3]]$check_name
#> [1] "Empty column"
#> 
#> [[3]]$column
#> [1] "mass"
#> 
#> [[3]]$status
#> [1] "PASS"
#> 
#> [[3]]$observed
#> [1] "Not empty"
#> 
#> [[3]]$threshold
#> [1] NA
#> 
#> [[3]]$message
#> [1] "Column 'mass' has at least one non-empty value."
#> 
#> 
#> [[4]]
#> [[4]]$check_id
#> [1] "QC-02"
#> 
#> [[4]]$check_name
#> [1] "Empty column"
#> 
#> [[4]]$column
#> [1] "hair_color"
#> 
#> [[4]]$status
#> [1] "PASS"
#> 
#> [[4]]$observed
#> [1] "Not empty"
#> 
#> [[4]]$threshold
#> [1] NA
#> 
#> [[4]]$message
#> [1] "Column 'hair_color' has at least one non-empty value."
#> 
#> 
#> [[5]]
#> [[5]]$check_id
#> [1] "QC-02"
#> 
#> [[5]]$check_name
#> [1] "Empty column"
#> 
#> [[5]]$column
#> [1] "skin_color"
#> 
#> [[5]]$status
#> [1] "PASS"
#> 
#> [[5]]$observed
#> [1] "Not empty"
#> 
#> [[5]]$threshold
#> [1] NA
#> 
#> [[5]]$message
#> [1] "Column 'skin_color' has at least one non-empty value."
#> 
#> 
#> [[6]]
#> [[6]]$check_id
#> [1] "QC-02"
#> 
#> [[6]]$check_name
#> [1] "Empty column"
#> 
#> [[6]]$column
#> [1] "eye_color"
#> 
#> [[6]]$status
#> [1] "PASS"
#> 
#> [[6]]$observed
#> [1] "Not empty"
#> 
#> [[6]]$threshold
#> [1] NA
#> 
#> [[6]]$message
#> [1] "Column 'eye_color' has at least one non-empty value."
#> 
#> 
#> [[7]]
#> [[7]]$check_id
#> [1] "QC-02"
#> 
#> [[7]]$check_name
#> [1] "Empty column"
#> 
#> [[7]]$column
#> [1] "birth_year"
#> 
#> [[7]]$status
#> [1] "PASS"
#> 
#> [[7]]$observed
#> [1] "Not empty"
#> 
#> [[7]]$threshold
#> [1] NA
#> 
#> [[7]]$message
#> [1] "Column 'birth_year' has at least one non-empty value."
#> 
#> 
#> [[8]]
#> [[8]]$check_id
#> [1] "QC-02"
#> 
#> [[8]]$check_name
#> [1] "Empty column"
#> 
#> [[8]]$column
#> [1] "sex"
#> 
#> [[8]]$status
#> [1] "PASS"
#> 
#> [[8]]$observed
#> [1] "Not empty"
#> 
#> [[8]]$threshold
#> [1] NA
#> 
#> [[8]]$message
#> [1] "Column 'sex' has at least one non-empty value."
#> 
#> 
#> [[9]]
#> [[9]]$check_id
#> [1] "QC-02"
#> 
#> [[9]]$check_name
#> [1] "Empty column"
#> 
#> [[9]]$column
#> [1] "gender"
#> 
#> [[9]]$status
#> [1] "PASS"
#> 
#> [[9]]$observed
#> [1] "Not empty"
#> 
#> [[9]]$threshold
#> [1] NA
#> 
#> [[9]]$message
#> [1] "Column 'gender' has at least one non-empty value."
#> 
#> 
#> [[10]]
#> [[10]]$check_id
#> [1] "QC-02"
#> 
#> [[10]]$check_name
#> [1] "Empty column"
#> 
#> [[10]]$column
#> [1] "homeworld"
#> 
#> [[10]]$status
#> [1] "PASS"
#> 
#> [[10]]$observed
#> [1] "Not empty"
#> 
#> [[10]]$threshold
#> [1] NA
#> 
#> [[10]]$message
#> [1] "Column 'homeworld' has at least one non-empty value."
#> 
#> 
#> [[11]]
#> [[11]]$check_id
#> [1] "QC-02"
#> 
#> [[11]]$check_name
#> [1] "Empty column"
#> 
#> [[11]]$column
#> [1] "species"
#> 
#> [[11]]$status
#> [1] "PASS"
#> 
#> [[11]]$observed
#> [1] "Not empty"
#> 
#> [[11]]$threshold
#> [1] NA
#> 
#> [[11]]$message
#> [1] "Column 'species' has at least one non-empty value."
#> 
#> 
#> [[12]]
#> [[12]]$check_id
#> [1] "QC-02"
#> 
#> [[12]]$check_name
#> [1] "Empty column"
#> 
#> [[12]]$column
#> [1] "films"
#> 
#> [[12]]$status
#> [1] "PASS"
#> 
#> [[12]]$observed
#> [1] "Not empty"
#> 
#> [[12]]$threshold
#> [1] NA
#> 
#> [[12]]$message
#> [1] "Column 'films' has at least one non-empty value."
#> 
#> 
#> [[13]]
#> [[13]]$check_id
#> [1] "QC-02"
#> 
#> [[13]]$check_name
#> [1] "Empty column"
#> 
#> [[13]]$column
#> [1] "vehicles"
#> 
#> [[13]]$status
#> [1] "PASS"
#> 
#> [[13]]$observed
#> [1] "Not empty"
#> 
#> [[13]]$threshold
#> [1] NA
#> 
#> [[13]]$message
#> [1] "Column 'vehicles' has at least one non-empty value."
#> 
#> 
#> [[14]]
#> [[14]]$check_id
#> [1] "QC-02"
#> 
#> [[14]]$check_name
#> [1] "Empty column"
#> 
#> [[14]]$column
#> [1] "starships"
#> 
#> [[14]]$status
#> [1] "PASS"
#> 
#> [[14]]$observed
#> [1] "Not empty"
#> 
#> [[14]]$threshold
#> [1] NA
#> 
#> [[14]]$message
#> [1] "Column 'starships' has at least one non-empty value."
#> 
#> 
```
