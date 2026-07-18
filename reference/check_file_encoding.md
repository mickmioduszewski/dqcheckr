# QC-16: File encoding sanity

Verifies that the delivered file's bytes matched the encoding declared
in the config.
[`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)
scans the whole file for UTF-8 validity before parsing (when the
effective encoding is UTF-8) and records the outcome on the returned
data frame; this check turns that outcome into a result:

- **PASS** when the file was valid UTF-8 as declared, or when a declared
  single-byte encoding (e.g. `ISO-8859-1`, `Windows-1252`) made a
  validity scan meaningless – every byte sequence is valid in those
  encodings by construction.

- **FAIL** when the file was not valid UTF-8 as declared. The run still
  completes: the file is read using a single-byte fallback encoding, and
  the message reports the detector's best guess at the actual encoding
  so the config can be corrected.

- **WARN** when the declared encoding is multi-byte or unknown (e.g.
  `UTF-16LE`, `Shift-JIS`): dqcheckr scans only UTF-8, so such a file is
  read as declared but its validity is not verified – it is never
  reported as "valid by construction".

- **WARN** when the UTF-8 scan itself could not complete (for example
  out of memory on a very large delivery): validity is unknown, so it is
  neither a clean PASS nor a definitive FAIL.

A supplier can change their export encoding between deliveries, which is
why this runs against every delivery rather than only at configuration
time. Returns an empty list when `df` did not come from
[`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)
(no scan outcome to report).

## Usage

``` r
check_file_encoding(df, config)
```

## Arguments

- df:

  A data frame with all columns as character vectors (as returned by
  [`read_dataset`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)).

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).
  Present for interface consistency; the scan outcome travels with `df`.

## Value

A list with one
[`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
object, or an empty list when no scan outcome is attached to `df`.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
check_file_encoding(df, cfg)
#> [[1]]
#> [[1]]$check_id
#> [1] "QC-16"
#> 
#> [[1]]$check_name
#> [1] "File encoding"
#> 
#> [[1]]$column
#> [1] NA
#> 
#> [[1]]$status
#> [1] "PASS"
#> 
#> [[1]]$observed
#> [1] "File is valid UTF-8."
#> 
#> [[1]]$threshold
#> [1] "declared: UTF-8"
#> 
#> [[1]]$message
#> [1] "File encoding matches the configuration."
#> 
#> 
```
