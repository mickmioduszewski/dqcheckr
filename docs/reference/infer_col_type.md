# Infer the logical type of a character column

Infer the logical type of a character column

## Usage

``` r
infer_col_type(x, threshold = 0.9)
```

## Arguments

- threshold:

  Numeric. Minimum proportion of non-empty values that must parse as
  numeric for the column to be classified as `"numeric"`. Defaults to
  `0.90`.
