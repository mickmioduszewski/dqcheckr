# Load and merge dataset configuration

Reads the global `dqcheckr.yml` and the dataset-specific YAML, merging
`rule_overrides` from the dataset config on top of `default_rules` from
the global config. Top-level keys `snapshot_db` and `report_output_dir`
are inherited from the global config when absent from the dataset
config.

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
cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
cfg <- load_config("starwars_csv", config_dir = cfg_dir)
cfg$format
#> [1] "csv"
```
