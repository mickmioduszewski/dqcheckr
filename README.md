# dqcheckr

Automated data quality checks for recurring dataset deliveries.

For each new file arrival, `dqcheckr` runs a battery of quality checks,
compares the file to the previous delivery, writes a self-contained HTML
report, and records summary statistics in a local SQLite database so that
quality trends can be tracked over time. Supports CSV and fixed-width formats.
Custom organisation-specific checks can be supplied as plain R files.

This is a CLI/API package — no UI. If you'd rather configure and run checks
without writing R code, see
[dqcheckrGUI](https://github.com/mickmioduszewski/dqcheckrGUI), a Shiny
front-end built on top of this package.

## What it does

- Runs single-snapshot quality checks (schema, missing rates, types, patterns,
  bounds, and more) against an incoming file
- Compares the file to the previous delivery (row/column differences, drift)
- Writes a self-contained HTML report for each run
- Records summary statistics in a SQLite snapshot database for long-term trend
  tracking and historical drift comparison
- Lets you supply your own organisation-specific checks as plain R files

## Installation

```r
install.packages("dqcheckr")

# or, the development version from GitHub
devtools::install_github("mickmioduszewski/dqcheckr")
```

## Usage

A data officer runs a single command for each arriving dataset:

```r
library(dqcheckr)

run_dq_check("customer_accounts", config_dir = "path/to/configs")
```

This prints a one-line console summary, writes an HTML report, and returns
`list(status, report_path, snapshot_id)` invisibly.

Two YAML files control every run: a global `dqcheckr.yml` (default thresholds
shared across datasets) and a per-dataset `<dataset_name>.yml` (file location,
expected columns, column-level rules and overrides).

## Learn more

See `vignette("dqcheckr")` for a full walkthrough of configuration and the
available checks, or the [package documentation
site](https://mickmioduszewski.github.io/dqcheckr/).

## License

MIT
