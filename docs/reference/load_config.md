# Load and merge dataset configuration

Reads the global `dqcheckr.yml` and the dataset-specific YAML, merging
`rule_overrides` from the dataset config on top of `default_rules` from
the global config.

## Usage

``` r
load_config(dataset_name, config_dir)
```

## Arguments

- dataset_name:

  Character. Dataset name; must match `<dataset_name>.yml` in
  `config_dir`.

- config_dir:

  Character. Path to the directory containing both YAML files.

## Value

A named list representing the merged configuration.

## Examples

``` r
if (FALSE) { # \dontrun{
cfg <- load_config("my_dataset", config_dir = "config")
cfg$format
} # }
```
