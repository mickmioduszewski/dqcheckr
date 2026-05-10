# =============================================================================
# demo.R — Named-file mode: CSV and FWF data quality checks
# =============================================================================
#
# Runs dqcheckr against the Star Wars dataset in two formats:
#   data/starwars.csv   — comma-separated file
#   data/starwars.fwf   — fixed-width file (same data)
#
# Both use explicit current_file: paths in their config (no folder scan).
# Results are written to output/reports/ and output/snapshots.sqlite.
#
# HOW TO RUN
#   1. Copy this demonstrations/ folder to a local directory:
#        dest <- file.path(path.expand("~"), "dqcheckr_demo")
#        file.copy(system.file("demonstrations", package = "dqcheckr"),
#                  dirname(dest), recursive = TRUE)
#        file.rename(file.path(dirname(dest), "demonstrations"), dest)
#   2. Open demo.R in RStudio and set the working directory to this folder:
#        Session -> Set Working Directory -> To Source File Location
#   3. Run the script (Ctrl+Enter or Source).
# =============================================================================

library(dqcheckr)

result_csv <- run_dq_check("starwars_csv", config_dir = "config", open_report = TRUE)
result_fwf <- run_dq_check("starwars_fwf", config_dir = "config", open_report = TRUE)

cat("\nCSV: status =", result_csv$status, "| report:", basename(result_csv$report_path), "\n")
cat("FWF: status =", result_fwf$status, "| report:", basename(result_fwf$report_path), "\n")
