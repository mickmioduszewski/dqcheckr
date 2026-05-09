# dqcheckr

Automated data quality checks for recurring dataset deliveries.

For each new file arrival, `dqcheckr` runs single-snapshot quality checks,
compares the file to the previous delivery, writes a self-contained HTML report,
and records summary statistics in a local SQLite database for long-term trend
tracking. Supports CSV and fixed-width (FWF) formats. Custom
organisation-specific checks can be supplied as plain R files.

## Installation

```r
# Install from a local source directory
devtools::install("path/to/dqcheckr")
```

## Quick start

Create two YAML files in a `config/` directory:

**`config/dqcheckr.yml`** — global defaults:

```yaml
snapshot_db: output/snapshots.sqlite
report_output_dir: output/reports/
default_rules:
  max_missing_rate: 0.05
  min_row_count: 0
```

**`config/my_dataset.yml`** — dataset-specific settings:

```yaml
folder: data/
format: csv
```

Then run:

```r
library(dqcheckr)

result <- run_dq_check("my_dataset", config_dir = "config")
result$status      # "PASS", "WARN", or "FAIL"
result$report_path # path to the HTML report
```

The HTML report opens automatically in your browser (in interactive sessions).
Historical run data accumulates in the SQLite snapshot database and is shown as
a trend chart in subsequent reports.

## Custom checks

Supply a plain R file that defines a `custom_checks(df)` function returning a
list of `dq_result()` objects:

```r
# config/my_checks.R
custom_checks <- function(df) {
  list(
    dq_result("CC-01", "Revenue positive",
              column  = "revenue",
              status  = if (any(as.numeric(df$revenue) < 0, na.rm = TRUE)) "FAIL" else "PASS",
              observed = "checked",
              message  = "Revenue must be non-negative.")
  )
}
```

Point to it in your dataset YAML:

```yaml
custom_checks_file: config/my_checks.R
```

## Learn more

See `vignette("dqcheckr")` for a full description of all configuration options,
every check (QC-01 to QC-14, SC-01/02, CP-01 to CP-08), and a worked example
using the Star Wars dataset.
