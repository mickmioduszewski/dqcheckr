# Infer the logical type of a character column

Classifies a character vector as `"date"`, `"numeric"`, `"character"`,
or `"unknown"` by applying rules in priority order.

## Usage

``` r
infer_col_type(x, threshold = 0.9)
```

## Arguments

- x:

  Character vector to classify (as read from a CSV or FWF file).

- threshold:

  Numeric. Minimum proportion of non-empty values that must parse as
  numeric for the column to be classified as `"numeric"`. Defaults to
  `0.90`. Configurable via `type_inference_threshold` in
  `rule_overrides`.

## Value

A single character string: `"date"`, `"numeric"`, `"character"`, or
`"unknown"`.

## Examples

``` r
infer_col_type(c("2024-01-01", "2024-06-15"))   # "date"
#> [1] "date"
infer_col_type(c("1.5", "2.0", "3.1"))          # "numeric"
#> [1] "numeric"
infer_col_type(c("high", "low", "medium"))       # "character"
#> [1] "character"
infer_col_type(c(NA, "", NA))                    # "unknown"
#> [1] "unknown"
infer_col_type(c(rep("1", 17), "a", "b", "c"), threshold = 0.80)  # "numeric"
#> [1] "numeric"
```
