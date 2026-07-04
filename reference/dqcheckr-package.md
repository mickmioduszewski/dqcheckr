# dqcheckr: Automated Data Quality Checks for Recurring Dataset Deliveries

Automates quality verification of recurring external dataset deliveries.
For each new file arrival, it runs single-snapshot quality checks (QC-01
to QC-15, SC-01/SC-02), compares the file to the previous delivery
(CP-01 to CP-08), writes a self-contained 'HTML' report, and records
summary statistics in a local 'SQLite' database for long-term trend
tracking. Supports 'CSV' and fixed-width formats. Custom
organisation-specific checks can be supplied as plain R files.

## Details

The main entry point is
[`run_dq_check`](https://mickmioduszewski.github.io/dqcheckr/reference/run_dq_check.md).
Configuration is driven by two 'YAML' files: a global `dqcheckr.yml` and
a per-dataset `<dataset_name>.yml`.

These packages are only called from the report templates rendered by
Quarto in a separate process (`inst/templates/*.qmd`), so static
analysis of `R/` cannot see them as used – without a reference here,
`R CMD check` reports "Namespaces in Imports field not imported from".

## See also

Useful links:

- <https://github.com/mickmioduszewski/dqcheckr>

- Report bugs at <https://github.com/mickmioduszewski/dqcheckr/issues>

## Author

**Maintainer**: Mick Mioduszewski <mick@mioduszewski.net>

Authors:

- Mick Mioduszewski <mick@mioduszewski.net>
