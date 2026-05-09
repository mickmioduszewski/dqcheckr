# Construct a data quality result object

Creates the atomic result unit returned by every check function.

## Usage

``` r
dq_result(
  check_id,
  check_name,
  column = NA_character_,
  status,
  observed,
  threshold = NA_character_,
  message
)
```

## Arguments

- check_id:

  Character. Short identifier for the check (e.g. `"QC-01"`).

- check_name:

  Character. Human-readable name of the check.

- column:

  Character. Column the check applies to, or `NA_character_` for
  row-level or file-level checks.

- status:

  Character. One of `"PASS"`, `"WARN"`, `"FAIL"`, or `"INFO"`.

- observed:

  Character. What was observed (e.g. `"5.2% missing"`).

- threshold:

  Character. The configured threshold, or `NA_character_` if not
  applicable.

- message:

  Character. Human-readable description of the result.

## Value

A named list with seven elements: `check_id`, `check_name`, `column`,
`status`, `observed`, `threshold`, `message`.

## Examples

``` r
dq_result("QC-01", "Missing rate", column = "age",
          status = "PASS", observed = "0% missing",
          message = "No missing values.")
#> $check_id
#> [1] "QC-01"
#> 
#> $check_name
#> [1] "Missing rate"
#> 
#> $column
#> [1] "age"
#> 
#> $status
#> [1] "PASS"
#> 
#> $observed
#> [1] "0% missing"
#> 
#> $threshold
#> [1] NA
#> 
#> $message
#> [1] "No missing values."
#> 
```
