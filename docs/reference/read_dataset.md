# Read a dataset file into a data frame

Reads a CSV or fixed-width file, coercing all columns to character and
trimming whitespace. Encoding and delimiter are taken from `config`.

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
  Must include `format` (`"csv"` or `"fwf"`). For FWF files,
  `fwf_widths` is required and `fwf_col_names` and `fwf_skip` are
  optional.

## Value

A data frame with all columns as character vectors.

## Examples

``` r
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
df   <- read_dataset(path, cfg)
```
