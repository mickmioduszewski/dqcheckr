#' dqcheckr: Automated Data Quality Checks for Recurring Dataset Deliveries
#'
#' Automates quality verification of recurring external dataset deliveries.
#' For each new file arrival, it runs single-snapshot quality checks (QC-01 to
#' QC-16, SC-01/SC-02), compares the file to the previous delivery (CP-01 to
#' CP-08), writes a self-contained 'HTML' report, and records summary statistics
#' in a local 'SQLite' database for long-term trend tracking. Supports 'CSV' and
#' fixed-width formats. Custom organisation-specific checks can be supplied as
#' plain R files.
#'
#' The main entry point is \code{\link{run_dq_check}}. Configuration is driven
#' by two 'YAML' files: a global \code{dqcheckr.yml} and a per-dataset
#' \code{<dataset_name>.yml}.
#'
#' These packages are only called from the report templates rendered by
#' Quarto in a separate process (\code{inst/templates/*.qmd}), so static
#' analysis of \code{R/} cannot see them as used -- without a reference here,
#' \code{R CMD check} reports "Namespaces in Imports field not imported from".
#' @importFrom kableExtra kbl kable_styling cell_spec
#' @importFrom ggplot2 ggplot aes geom_line geom_point geom_col labs
#' @importFrom ggplot2 scale_fill_manual theme_minimal
#' @importFrom gridExtra grid.arrange
#' @importFrom dplyr %>%
#' @importFrom tidyr pivot_longer
#' @importFrom knitr raw_html
#'
#' @keywords internal
"_PACKAGE"
