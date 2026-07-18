# Read a dataset file into a data frame

Reads a CSV or fixed-width file, coercing all columns to character and
trimming whitespace. Encoding and delimiter are taken from `config`. A
declared encoding of ASCII (or a formal alias such as `US-ASCII`) is
read as UTF-8: ASCII is a strict subset of UTF-8, so this is lossless,
and it protects against deliveries whose non-ASCII bytes appear beyond
any sample a sniffer looked at. When the effective encoding is UTF-8 the
whole file is validity-scanned before parsing; a delivery that is not
valid UTF-8 is read using a single-byte fallback encoding instead, and
the mismatch is surfaced by
[`check_file_encoding`](https://mickmioduszewski.github.io/dqcheckr/reference/check_file_encoding.md)
(QC-16) as a FAIL result rather than crashing the run.

## Usage

``` r
read_dataset(path, config)
```

## Arguments

- path:

  Character. Path to the file to read.

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).
  Must include `format` (`"csv"` or `"fwf"`). For CSV files, `col_names`
  (an explicit column-name list) and `csv_skip` (number of leading lines
  to drop, e.g. a real header row that is being replaced by `col_names`)
  are optional and default to using the file's own header and `0L`
  respectively. For FWF files, `fwf_widths` is required and
  `fwf_col_names` and `fwf_skip` are optional.

## Value

A data frame with all columns as character vectors.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
```
