# QC-14: Check row count bounds and optional file size

Runs up to four sub-checks, each returning a separate
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md):

1.  **Empty file** – FAIL when the file contains no data rows at all.
    Emitted unconditionally (independent of `min_row_count`) so that an
    empty delivery always fails the run.

2.  **File size** – only when `file_path` is supplied and
    `max_file_size_mb` is configured in `rules`: FAIL if the file
    exceeds the size limit.

3.  **Minimum row count** – FAIL if `row_count < min_row_count`. Skipped
    (PASS with a note) when `min_row_count` is `0`.

4.  **Maximum row count** – only when `max_row_count` is configured in
    `rules`: FAIL if `row_count > max_row_count`.

## Usage

``` r
check_min_row_count(df, config, file_path = NULL)
```

## Arguments

- df:

  A data frame with all columns as character vectors (as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

- file_path:

  Character or `NULL`. Absolute path to the file on disk, required for
  the optional file-size sub-check.

## Value

A list of
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
objects (one to four entries depending on which sub-checks are active).

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
check_min_row_count(df, cfg, file_path = path)
#> [[1]]
#> [[1]]$check_id
#> [1] "QC-14"
#> 
#> [[1]]$check_name
#> [1] "Minimum row count"
#> 
#> [[1]]$column
#> [1] NA
#> 
#> [[1]]$status
#> [1] "PASS"
#> 
#> [[1]]$observed
#> [1] "87 rows"
#> 
#> [[1]]$threshold
#> [1] "80 rows minimum"
#> 
#> [[1]]$message
#> [1] "File has 87 rows, meeting the minimum of 80."
#> 
#> 
```
