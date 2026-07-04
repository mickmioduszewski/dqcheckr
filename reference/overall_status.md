# Compute the worst status across a list of dq_result objects

Returns the single worst status in precedence order: `"FAIL"` \>
`"WARN"` \> `"PASS"` \> `"INFO"`.

## Usage

``` r
overall_status(results)
```

## Arguments

- results:

  A list of
  [`dq_result`](https://mickmioduszewski.github.io/dqcheckr/reference/dq_result.md)
  objects.

## Value

A single character string: `"FAIL"`, `"WARN"`, `"PASS"`, or `"INFO"`.

## Examples

``` r
r1 <- dq_result("QC-01", "test", status = "PASS", observed = "ok", message = "ok")
r2 <- dq_result("QC-02", "test", status = "WARN", observed = "ok", message = "ok")
overall_status(list(r1, r2))  # "WARN"
#> [1] "WARN"
```
