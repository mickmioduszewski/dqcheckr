# QC-06: Report inferred column types

Returns one `"INFO"`
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
per column recording the type resolved by
[`resolve_col_type`](https://mickmioduszewski.github.io/dqcheckr/reference/resolve_col_type.md)
(`"date"`, `"numeric"`, `"character"`, or `"unknown"`). Per-column
overrides from `config$column_types` are respected.

## Usage

``` r
check_inferred_types(df, config, types = NULL)
```

## Arguments

- df:

  A data frame with all columns as character vectors (as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

- types:

  Optional named character vector of pre-resolved column types (one
  element per column, as produced by
  [`resolve_col_type`](https://mickmioduszewski.github.io/dqcheckr/reference/resolve_col_type.md)).
  When `NULL` (the default), types are resolved internally. Supplying
  this avoids re-running type inference when several checks share one
  data frame.

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects, one per column, all with status `"INFO"`.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
check_inferred_types(df, cfg)
#> [[1]]
#> [[1]]$check_id
#> [1] "QC-06"
#> 
#> [[1]]$check_name
#> [1] "Inferred type"
#> 
#> [[1]]$column
#> [1] "name"
#> 
#> [[1]]$status
#> [1] "INFO"
#> 
#> [[1]]$observed
#> [1] "character"
#> 
#> [[1]]$threshold
#> [1] NA
#> 
#> [[1]]$message
#> [1] "Column 'name' inferred as character."
#> 
#> 
#> [[2]]
#> [[2]]$check_id
#> [1] "QC-06"
#> 
#> [[2]]$check_name
#> [1] "Inferred type"
#> 
#> [[2]]$column
#> [1] "height"
#> 
#> [[2]]$status
#> [1] "INFO"
#> 
#> [[2]]$observed
#> [1] "numeric"
#> 
#> [[2]]$threshold
#> [1] NA
#> 
#> [[2]]$message
#> [1] "Column 'height' inferred as numeric."
#> 
#> 
#> [[3]]
#> [[3]]$check_id
#> [1] "QC-06"
#> 
#> [[3]]$check_name
#> [1] "Inferred type"
#> 
#> [[3]]$column
#> [1] "mass"
#> 
#> [[3]]$status
#> [1] "INFO"
#> 
#> [[3]]$observed
#> [1] "numeric"
#> 
#> [[3]]$threshold
#> [1] NA
#> 
#> [[3]]$message
#> [1] "Column 'mass' inferred as numeric."
#> 
#> 
#> [[4]]
#> [[4]]$check_id
#> [1] "QC-06"
#> 
#> [[4]]$check_name
#> [1] "Inferred type"
#> 
#> [[4]]$column
#> [1] "hair_color"
#> 
#> [[4]]$status
#> [1] "INFO"
#> 
#> [[4]]$observed
#> [1] "character"
#> 
#> [[4]]$threshold
#> [1] NA
#> 
#> [[4]]$message
#> [1] "Column 'hair_color' inferred as character."
#> 
#> 
#> [[5]]
#> [[5]]$check_id
#> [1] "QC-06"
#> 
#> [[5]]$check_name
#> [1] "Inferred type"
#> 
#> [[5]]$column
#> [1] "skin_color"
#> 
#> [[5]]$status
#> [1] "INFO"
#> 
#> [[5]]$observed
#> [1] "character"
#> 
#> [[5]]$threshold
#> [1] NA
#> 
#> [[5]]$message
#> [1] "Column 'skin_color' inferred as character."
#> 
#> 
#> [[6]]
#> [[6]]$check_id
#> [1] "QC-06"
#> 
#> [[6]]$check_name
#> [1] "Inferred type"
#> 
#> [[6]]$column
#> [1] "eye_color"
#> 
#> [[6]]$status
#> [1] "INFO"
#> 
#> [[6]]$observed
#> [1] "character"
#> 
#> [[6]]$threshold
#> [1] NA
#> 
#> [[6]]$message
#> [1] "Column 'eye_color' inferred as character."
#> 
#> 
#> [[7]]
#> [[7]]$check_id
#> [1] "QC-06"
#> 
#> [[7]]$check_name
#> [1] "Inferred type"
#> 
#> [[7]]$column
#> [1] "birth_year"
#> 
#> [[7]]$status
#> [1] "INFO"
#> 
#> [[7]]$observed
#> [1] "numeric"
#> 
#> [[7]]$threshold
#> [1] NA
#> 
#> [[7]]$message
#> [1] "Column 'birth_year' inferred as numeric."
#> 
#> 
#> [[8]]
#> [[8]]$check_id
#> [1] "QC-06"
#> 
#> [[8]]$check_name
#> [1] "Inferred type"
#> 
#> [[8]]$column
#> [1] "sex"
#> 
#> [[8]]$status
#> [1] "INFO"
#> 
#> [[8]]$observed
#> [1] "character"
#> 
#> [[8]]$threshold
#> [1] NA
#> 
#> [[8]]$message
#> [1] "Column 'sex' inferred as character."
#> 
#> 
#> [[9]]
#> [[9]]$check_id
#> [1] "QC-06"
#> 
#> [[9]]$check_name
#> [1] "Inferred type"
#> 
#> [[9]]$column
#> [1] "gender"
#> 
#> [[9]]$status
#> [1] "INFO"
#> 
#> [[9]]$observed
#> [1] "character"
#> 
#> [[9]]$threshold
#> [1] NA
#> 
#> [[9]]$message
#> [1] "Column 'gender' inferred as character."
#> 
#> 
#> [[10]]
#> [[10]]$check_id
#> [1] "QC-06"
#> 
#> [[10]]$check_name
#> [1] "Inferred type"
#> 
#> [[10]]$column
#> [1] "homeworld"
#> 
#> [[10]]$status
#> [1] "INFO"
#> 
#> [[10]]$observed
#> [1] "character"
#> 
#> [[10]]$threshold
#> [1] NA
#> 
#> [[10]]$message
#> [1] "Column 'homeworld' inferred as character."
#> 
#> 
#> [[11]]
#> [[11]]$check_id
#> [1] "QC-06"
#> 
#> [[11]]$check_name
#> [1] "Inferred type"
#> 
#> [[11]]$column
#> [1] "species"
#> 
#> [[11]]$status
#> [1] "INFO"
#> 
#> [[11]]$observed
#> [1] "character"
#> 
#> [[11]]$threshold
#> [1] NA
#> 
#> [[11]]$message
#> [1] "Column 'species' inferred as character."
#> 
#> 
#> [[12]]
#> [[12]]$check_id
#> [1] "QC-06"
#> 
#> [[12]]$check_name
#> [1] "Inferred type"
#> 
#> [[12]]$column
#> [1] "films"
#> 
#> [[12]]$status
#> [1] "INFO"
#> 
#> [[12]]$observed
#> [1] "character"
#> 
#> [[12]]$threshold
#> [1] NA
#> 
#> [[12]]$message
#> [1] "Column 'films' inferred as character."
#> 
#> 
#> [[13]]
#> [[13]]$check_id
#> [1] "QC-06"
#> 
#> [[13]]$check_name
#> [1] "Inferred type"
#> 
#> [[13]]$column
#> [1] "vehicles"
#> 
#> [[13]]$status
#> [1] "INFO"
#> 
#> [[13]]$observed
#> [1] "character"
#> 
#> [[13]]$threshold
#> [1] NA
#> 
#> [[13]]$message
#> [1] "Column 'vehicles' inferred as character."
#> 
#> 
#> [[14]]
#> [[14]]$check_id
#> [1] "QC-06"
#> 
#> [[14]]$check_name
#> [1] "Inferred type"
#> 
#> [[14]]$column
#> [1] "starships"
#> 
#> [[14]]$status
#> [1] "INFO"
#> 
#> [[14]]$observed
#> [1] "character"
#> 
#> [[14]]$threshold
#> [1] NA
#> 
#> [[14]]$message
#> [1] "Column 'starships' inferred as character."
#> 
#> 
```
