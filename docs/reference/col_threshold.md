# Look up the effective threshold for a check, with per-column fallback

Resolution order: `column_rules.<col>.<key>` \> `rules.<key>` \>
`default`.

## Usage

``` r
col_threshold(config, col, key, default = NULL)
```

## Arguments

- config:

  Named list. Merged configuration.

- col:

  Character. Column name.

- key:

  Character. Threshold key (e.g. `"max_missing_rate"`).

- default:

  Default value if not found at any level.

## Value

The resolved threshold value.
