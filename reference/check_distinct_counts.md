# QC-08: Report distinct value counts for character columns

For each column whose resolved type is `"character"`, returns one
`"INFO"`
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
with the count of distinct non-empty values. Columns inferred as numeric
or date are silently skipped.

## Usage

``` r
check_distinct_counts(df, config, types = NULL)
```

## Arguments

- df:

  A data frame with all columns as character vectors (as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

- types:

  Optional named character vector of pre-resolved column types; see
  [`check_inferred_types`](https://mickmioduszewski.github.io/dqcheckr/reference/check_inferred_types.md).

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects (one per character column), all with status `"INFO"`. Returns an
empty list if no character columns are found.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
check_distinct_counts(df, cfg)
#> [[1]]
#> [[1]]$check_id
#> [1] "QC-08"
#> 
#> [[1]]$check_name
#> [1] "Distinct value count"
#> 
#> [[1]]$column
#> [1] "name"
#> 
#> [[1]]$status
#> [1] "INFO"
#> 
#> [[1]]$observed
#> [1] "87"
#> 
#> [[1]]$threshold
#> [1] NA
#> 
#> [[1]]$message
#> [1] "Column 'name' has 87 distinct non-empty value(s)."
#> 
#> 
#> [[2]]
#> [[2]]$check_id
#> [1] "QC-08"
#> 
#> [[2]]$check_name
#> [1] "Distinct value count"
#> 
#> [[2]]$column
#> [1] "hair_color"
#> 
#> [[2]]$status
#> [1] "INFO"
#> 
#> [[2]]$observed
#> [1] "11"
#> 
#> [[2]]$threshold
#> [1] NA
#> 
#> [[2]]$message
#> [1] "Column 'hair_color' has 11 distinct non-empty value(s)."
#> 
#> 
#> [[3]]
#> [[3]]$check_id
#> [1] "QC-08"
#> 
#> [[3]]$check_name
#> [1] "Distinct value count"
#> 
#> [[3]]$column
#> [1] "skin_color"
#> 
#> [[3]]$status
#> [1] "INFO"
#> 
#> [[3]]$observed
#> [1] "31"
#> 
#> [[3]]$threshold
#> [1] NA
#> 
#> [[3]]$message
#> [1] "Column 'skin_color' has 31 distinct non-empty value(s)."
#> 
#> 
#> [[4]]
#> [[4]]$check_id
#> [1] "QC-08"
#> 
#> [[4]]$check_name
#> [1] "Distinct value count"
#> 
#> [[4]]$column
#> [1] "eye_color"
#> 
#> [[4]]$status
#> [1] "INFO"
#> 
#> [[4]]$observed
#> [1] "15"
#> 
#> [[4]]$threshold
#> [1] NA
#> 
#> [[4]]$message
#> [1] "Column 'eye_color' has 15 distinct non-empty value(s)."
#> 
#> 
#> [[5]]
#> [[5]]$check_id
#> [1] "QC-08"
#> 
#> [[5]]$check_name
#> [1] "Distinct value count"
#> 
#> [[5]]$column
#> [1] "sex"
#> 
#> [[5]]$status
#> [1] "INFO"
#> 
#> [[5]]$observed
#> [1] "4"
#> 
#> [[5]]$threshold
#> [1] NA
#> 
#> [[5]]$message
#> [1] "Column 'sex' has 4 distinct non-empty value(s)."
#> 
#> 
#> [[6]]
#> [[6]]$check_id
#> [1] "QC-08"
#> 
#> [[6]]$check_name
#> [1] "Distinct value count"
#> 
#> [[6]]$column
#> [1] "gender"
#> 
#> [[6]]$status
#> [1] "INFO"
#> 
#> [[6]]$observed
#> [1] "2"
#> 
#> [[6]]$threshold
#> [1] NA
#> 
#> [[6]]$message
#> [1] "Column 'gender' has 2 distinct non-empty value(s)."
#> 
#> 
#> [[7]]
#> [[7]]$check_id
#> [1] "QC-08"
#> 
#> [[7]]$check_name
#> [1] "Distinct value count"
#> 
#> [[7]]$column
#> [1] "homeworld"
#> 
#> [[7]]$status
#> [1] "INFO"
#> 
#> [[7]]$observed
#> [1] "48"
#> 
#> [[7]]$threshold
#> [1] NA
#> 
#> [[7]]$message
#> [1] "Column 'homeworld' has 48 distinct non-empty value(s)."
#> 
#> 
#> [[8]]
#> [[8]]$check_id
#> [1] "QC-08"
#> 
#> [[8]]$check_name
#> [1] "Distinct value count"
#> 
#> [[8]]$column
#> [1] "species"
#> 
#> [[8]]$status
#> [1] "INFO"
#> 
#> [[8]]$observed
#> [1] "37"
#> 
#> [[8]]$threshold
#> [1] NA
#> 
#> [[8]]$message
#> [1] "Column 'species' has 37 distinct non-empty value(s)."
#> 
#> 
#> [[9]]
#> [[9]]$check_id
#> [1] "QC-08"
#> 
#> [[9]]$check_name
#> [1] "Distinct value count"
#> 
#> [[9]]$column
#> [1] "films"
#> 
#> [[9]]$status
#> [1] "INFO"
#> 
#> [[9]]$observed
#> [1] "24"
#> 
#> [[9]]$threshold
#> [1] NA
#> 
#> [[9]]$message
#> [1] "Column 'films' has 24 distinct non-empty value(s)."
#> 
#> 
#> [[10]]
#> [[10]]$check_id
#> [1] "QC-08"
#> 
#> [[10]]$check_name
#> [1] "Distinct value count"
#> 
#> [[10]]$column
#> [1] "vehicles"
#> 
#> [[10]]$status
#> [1] "INFO"
#> 
#> [[10]]$observed
#> [1] "10"
#> 
#> [[10]]$threshold
#> [1] NA
#> 
#> [[10]]$message
#> [1] "Column 'vehicles' has 10 distinct non-empty value(s)."
#> 
#> 
#> [[11]]
#> [[11]]$check_id
#> [1] "QC-08"
#> 
#> [[11]]$check_name
#> [1] "Distinct value count"
#> 
#> [[11]]$column
#> [1] "starships"
#> 
#> [[11]]$status
#> [1] "INFO"
#> 
#> [[11]]$observed
#> [1] "15"
#> 
#> [[11]]$threshold
#> [1] NA
#> 
#> [[11]]$message
#> [1] "Column 'starships' has 15 distinct non-empty value(s)."
#> 
#> 
```
