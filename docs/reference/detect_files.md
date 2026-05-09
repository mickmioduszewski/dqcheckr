# Detect current and previous dataset files

Resolves the current and previous file paths from the configuration. If
`current_file` is set explicitly, it is used directly. Otherwise the two
most recently modified files in `folder` are used.

## Usage

``` r
detect_files(config)
```

## Arguments

- config:

  Named list. Merged configuration as returned by
  [`load_config`](https://mickmioduszewski.github.io/dqcheckr/reference/load_config.md).

## Value

A named list with elements `current` (character path) and `previous`
(character path or `NULL`).

## Examples

``` r
if (FALSE) { # \dontrun{
cfg <- load_config("my_dataset", "config")
files <- detect_files(cfg)
files$current
} # }
```
