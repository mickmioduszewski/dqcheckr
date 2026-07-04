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
objects (one to three entries depending on which sub-checks are active).

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
#> Error in value[[3L]](cond): Failed to parse file '': does not exist in current working directory:
#> /home/runner/work/dqcheckr/dqcheckr/docs/reference.
check_min_row_count(df, cfg, file_path = path)
#> Error in if (nrow(df) == 0) {    results <- c(results, list(dq_result(check_id = "QC-14",         check_name = "Empty file", status = "FAIL", observed = "0 rows",         message = "File contains no data rows.")))}: argument is of length zero
```
