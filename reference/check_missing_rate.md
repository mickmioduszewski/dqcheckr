# QC-01: Check missing rate per column

Returns a
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
per column flagging columns whose proportion of missing or empty values
exceeds `max_missing_rate`.

## Usage

``` r
check_missing_rate(df, config)
```

## Arguments

- df:

  A data frame with all columns as character vectors.

- config:

  Named list as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects, one per column.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
check_missing_rate(df, cfg)
#> [[1]]
#> [[1]]$check_id
#> [1] "QC-01"
#> 
#> [[1]]$check_name
#> [1] "Missing rate"
#> 
#> [[1]]$column
#> [1] "name"
#> 
#> [[1]]$status
#> [1] "PASS"
#> 
#> [[1]]$observed
#> [1] "0.0% missing (0 of 87)"
#> 
#> [[1]]$threshold
#> [1] "60.0%"
#> 
#> [[1]]$message
#> [1] "Column 'name' missing rate is within threshold."
#> 
#> 
#> [[2]]
#> [[2]]$check_id
#> [1] "QC-01"
#> 
#> [[2]]$check_name
#> [1] "Missing rate"
#> 
#> [[2]]$column
#> [1] "height"
#> 
#> [[2]]$status
#> [1] "PASS"
#> 
#> [[2]]$observed
#> [1] "6.9% missing (6 of 87)"
#> 
#> [[2]]$threshold
#> [1] "60.0%"
#> 
#> [[2]]$message
#> [1] "Column 'height' missing rate is within threshold."
#> 
#> 
#> [[3]]
#> [[3]]$check_id
#> [1] "QC-01"
#> 
#> [[3]]$check_name
#> [1] "Missing rate"
#> 
#> [[3]]$column
#> [1] "mass"
#> 
#> [[3]]$status
#> [1] "PASS"
#> 
#> [[3]]$observed
#> [1] "32.2% missing (28 of 87)"
#> 
#> [[3]]$threshold
#> [1] "60.0%"
#> 
#> [[3]]$message
#> [1] "Column 'mass' missing rate is within threshold."
#> 
#> 
#> [[4]]
#> [[4]]$check_id
#> [1] "QC-01"
#> 
#> [[4]]$check_name
#> [1] "Missing rate"
#> 
#> [[4]]$column
#> [1] "hair_color"
#> 
#> [[4]]$status
#> [1] "PASS"
#> 
#> [[4]]$observed
#> [1] "5.7% missing (5 of 87)"
#> 
#> [[4]]$threshold
#> [1] "60.0%"
#> 
#> [[4]]$message
#> [1] "Column 'hair_color' missing rate is within threshold."
#> 
#> 
#> [[5]]
#> [[5]]$check_id
#> [1] "QC-01"
#> 
#> [[5]]$check_name
#> [1] "Missing rate"
#> 
#> [[5]]$column
#> [1] "skin_color"
#> 
#> [[5]]$status
#> [1] "PASS"
#> 
#> [[5]]$observed
#> [1] "0.0% missing (0 of 87)"
#> 
#> [[5]]$threshold
#> [1] "60.0%"
#> 
#> [[5]]$message
#> [1] "Column 'skin_color' missing rate is within threshold."
#> 
#> 
#> [[6]]
#> [[6]]$check_id
#> [1] "QC-01"
#> 
#> [[6]]$check_name
#> [1] "Missing rate"
#> 
#> [[6]]$column
#> [1] "eye_color"
#> 
#> [[6]]$status
#> [1] "PASS"
#> 
#> [[6]]$observed
#> [1] "0.0% missing (0 of 87)"
#> 
#> [[6]]$threshold
#> [1] "60.0%"
#> 
#> [[6]]$message
#> [1] "Column 'eye_color' missing rate is within threshold."
#> 
#> 
#> [[7]]
#> [[7]]$check_id
#> [1] "QC-01"
#> 
#> [[7]]$check_name
#> [1] "Missing rate"
#> 
#> [[7]]$column
#> [1] "birth_year"
#> 
#> [[7]]$status
#> [1] "PASS"
#> 
#> [[7]]$observed
#> [1] "50.6% missing (44 of 87)"
#> 
#> [[7]]$threshold
#> [1] "60.0%"
#> 
#> [[7]]$message
#> [1] "Column 'birth_year' missing rate is within threshold."
#> 
#> 
#> [[8]]
#> [[8]]$check_id
#> [1] "QC-01"
#> 
#> [[8]]$check_name
#> [1] "Missing rate"
#> 
#> [[8]]$column
#> [1] "sex"
#> 
#> [[8]]$status
#> [1] "PASS"
#> 
#> [[8]]$observed
#> [1] "4.6% missing (4 of 87)"
#> 
#> [[8]]$threshold
#> [1] "60.0%"
#> 
#> [[8]]$message
#> [1] "Column 'sex' missing rate is within threshold."
#> 
#> 
#> [[9]]
#> [[9]]$check_id
#> [1] "QC-01"
#> 
#> [[9]]$check_name
#> [1] "Missing rate"
#> 
#> [[9]]$column
#> [1] "gender"
#> 
#> [[9]]$status
#> [1] "PASS"
#> 
#> [[9]]$observed
#> [1] "4.6% missing (4 of 87)"
#> 
#> [[9]]$threshold
#> [1] "60.0%"
#> 
#> [[9]]$message
#> [1] "Column 'gender' missing rate is within threshold."
#> 
#> 
#> [[10]]
#> [[10]]$check_id
#> [1] "QC-01"
#> 
#> [[10]]$check_name
#> [1] "Missing rate"
#> 
#> [[10]]$column
#> [1] "homeworld"
#> 
#> [[10]]$status
#> [1] "PASS"
#> 
#> [[10]]$observed
#> [1] "11.5% missing (10 of 87)"
#> 
#> [[10]]$threshold
#> [1] "60.0%"
#> 
#> [[10]]$message
#> [1] "Column 'homeworld' missing rate is within threshold."
#> 
#> 
#> [[11]]
#> [[11]]$check_id
#> [1] "QC-01"
#> 
#> [[11]]$check_name
#> [1] "Missing rate"
#> 
#> [[11]]$column
#> [1] "species"
#> 
#> [[11]]$status
#> [1] "PASS"
#> 
#> [[11]]$observed
#> [1] "4.6% missing (4 of 87)"
#> 
#> [[11]]$threshold
#> [1] "60.0%"
#> 
#> [[11]]$message
#> [1] "Column 'species' missing rate is within threshold."
#> 
#> 
#> [[12]]
#> [[12]]$check_id
#> [1] "QC-01"
#> 
#> [[12]]$check_name
#> [1] "Missing rate"
#> 
#> [[12]]$column
#> [1] "films"
#> 
#> [[12]]$status
#> [1] "PASS"
#> 
#> [[12]]$observed
#> [1] "0.0% missing (0 of 87)"
#> 
#> [[12]]$threshold
#> [1] "60.0%"
#> 
#> [[12]]$message
#> [1] "Column 'films' missing rate is within threshold."
#> 
#> 
#> [[13]]
#> [[13]]$check_id
#> [1] "QC-01"
#> 
#> [[13]]$check_name
#> [1] "Missing rate"
#> 
#> [[13]]$column
#> [1] "vehicles"
#> 
#> [[13]]$status
#> [1] "FAIL"
#> 
#> [[13]]$observed
#> [1] "87.4% missing (76 of 87)"
#> 
#> [[13]]$threshold
#> [1] "60.0%"
#> 
#> [[13]]$message
#> [1] "Column 'vehicles' missing rate 87.4% exceeds threshold 60.0%."
#> 
#> 
#> [[14]]
#> [[14]]$check_id
#> [1] "QC-01"
#> 
#> [[14]]$check_name
#> [1] "Missing rate"
#> 
#> [[14]]$column
#> [1] "starships"
#> 
#> [[14]]$status
#> [1] "FAIL"
#> 
#> [[14]]$observed
#> [1] "77.0% missing (67 of 87)"
#> 
#> [[14]]$threshold
#> [1] "60.0%"
#> 
#> [[14]]$message
#> [1] "Column 'starships' missing rate 77.0% exceeds threshold 60.0%."
#> 
#> 
```
