# Extracted from test-sniff.R:128

# prequel ----------------------------------------------------------------------
sniff_file <- function(lines, ext = ".csv") {
  f <- tempfile(fileext = ext)
  writeLines(lines, f)
  f
}

# test -------------------------------------------------------------------------
d <- file.path(tempdir(), paste0("blankhdr_", sample.int(1e9, 1)))
dir.create(d)
on.exit(unlink(d, recursive = TRUE))
writeLines(c("id,amount,", "A1,10,", "A2,20,"), file.path(d, "orders.csv"))
writeLines('snapshot_db: "snap.sqlite"', file.path(d, "dqcheckr.yml"))
suppressMessages(generate_dataset_config(file.path(d, "orders.csv"), config_dir = d))
v <- validate_config("orders", config_dir = d)
expect_true(v$valid)
expect_equal(nrow(v$findings), 0L)
