# =============================================================================
# demo2.R — Folder-scan mode with version comparison and custom checks
# =============================================================================
#
# Demonstrates dqcheckr's folder-scan file detection, version comparison,
# and custom checks.
#
# data2/ contains two deliveries of the Star Wars dataset:
#   starwars_v1.csv  — original data  (used as "previous" delivery)
#   starwars_v2.csv  — perturbed data (used as "current" delivery)
#
# The perturbed version passes all single-snapshot quality checks but shows
# measurable shifts in column distributions that the CP comparison checks
# will flag:
#   height     +15 to all values    (~8.6% mean shift)
#   mass       x1.10                (~10%  mean shift)
#   birth_year -5 to all values     (~5.7% mean shift)
#   homeworld  5 characters moved to "Exegol"  (new distinct value)
#   species    1 character changed to "Chiss"   (new distinct value)
#
# Custom checks (custom2/starwars_custom.R) add three human-specific rules:
#   CC-01 FAIL  Human height > 210
#   CC-02 WARN  Human height 200-210
#   CC-03 WARN  Human mass > 140
#
# HOW TO RUN
#   1. Copy this demonstrations/ folder to a local directory:
#        dest <- file.path(path.expand("~"), "dqcheckr_demo")
#        file.copy(system.file("demonstrations", package = "dqcheckr"),
#                  dirname(dest), recursive = TRUE)
#        file.rename(file.path(dirname(dest), "demonstrations"), dest)
#   2. Open demo2.R in RStudio and set the working directory to this folder:
#        Session -> Set Working Directory -> To Source File Location
#   3. Run the script (Ctrl+Enter or Source).
# =============================================================================

library(dqcheckr)

# Ensure v1 is stamped as older than v2 so folder scan picks v2 as current.
# This is needed because file copy resets timestamps.
Sys.setFileTime("data2/starwars_v1.csv", Sys.time() - 3600)

result <- run_dq_check("starwars_folder", config_dir = "config2", open_report = TRUE)

cat("\nStatus     :", result$status, "\n")
cat("Report     :", result$report_path, "\n")
cat("Snapshot ID:", result$snapshot_id, "\n")
