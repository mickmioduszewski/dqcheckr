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
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg <- load_config("starwars_csv", config_dir = cfg_dir)
cfg$current_file <- system.file("demonstrations/data/starwars.csv",
                                 package = "dqcheckr")
files <- detect_files(cfg)
files$current
#> [1] "/home/runner/work/_temp/Library/dqcheckr/demonstrations/data/starwars.csv"
```
