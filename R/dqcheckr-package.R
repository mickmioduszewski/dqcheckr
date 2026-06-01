#' dqcheckr: Automated Data Quality Checks for Recurring Dataset Deliveries
#'
#' Automates quality verification of recurring external dataset deliveries.
#' For each new file arrival, it runs single-snapshot quality checks (QC-01 to
#' QC-15, SC-01/SC-02), compares the file to the previous delivery (CP-01 to
#' CP-08), writes a self-contained 'HTML' report, and records summary statistics
#' in a local 'SQLite' database for long-term trend tracking. Supports 'CSV' and
#' fixed-width formats. Custom organisation-specific checks can be supplied as
#' plain R files.
#'
#' The main entry point is \code{\link{run_dq_check}}. Configuration is driven
#' by two 'YAML' files: a global \code{dqcheckr.yml} and a per-dataset
#' \code{<dataset_name>.yml}.
#'
#' @keywords internal
#' @noRd
#'
#' The importFrom directives below are not called by any R function in this
#' package directly. They are declared here so that R CMD check recognises
#' them as used imports (satisfying DESCRIPTION Imports) and so that the
#' symbols are available on the search path when the Quarto report template
#' (inst/templates/report.qmd) is executed by knitr during rendering.
#' @importFrom kableExtra kbl kable_styling cell_spec
#' @importFrom ggplot2 ggplot aes geom_line geom_point geom_col labs
#' @importFrom ggplot2 scale_fill_manual theme_minimal
#' @importFrom gridExtra grid.arrange
#' @importFrom dplyr %>%
#' @importFrom tidyr pivot_longer
#' @importFrom knitr raw_html
"_PACKAGE"
