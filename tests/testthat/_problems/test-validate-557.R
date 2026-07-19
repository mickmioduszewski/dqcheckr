# Extracted from test-validate.R:557

# prequel ----------------------------------------------------------------------
vcfg <- function(global = 'snapshot_db: "snap.sqlite"',
                 dataset = c('dataset_name: "demo"', 'format: csv',
                             'current_file: "x.csv"'),
                 dataset_name = "demo") {
  dir <- file.path(tempdir(), paste0("vcfg_", sample.int(1e9, 1)))
  dir.create(dir)
  writeLines(global, file.path(dir, "dqcheckr.yml"))
  writeLines(dataset, file.path(dir, paste0(dataset_name, ".yml")))
  dir
}
sev_of  <- function(v, key) v$findings$severity[v$findings$key == key]
msgs_of <- function(v, key) v$findings$message[v$findings$key == key]
vcfg2 <- function(content, dataset = character(), format = "csv",
                  file_ext = ".csv") {
  data_file <- tempfile(fileext = file_ext)
  writeLines(content, data_file)
  dir <- vcfg(dataset = c('dataset_name: "demo"',
                          sprintf("format: %s", format),
                          sprintf('current_file: "%s"',
                                  gsub("\\\\", "/", data_file)),
                          dataset))
  attr(dir, "data_file") <- data_file
  dir
}
cleanup2 <- function(dir) unlink(c(attr(dir, "data_file"), dir), recursive = TRUE)

# test -------------------------------------------------------------------------
dir <- vcfg2("AB12XY", format = "fwf", file_ext = ".txt",
               dataset = "fwf_widths: [2, 2, 4]")
on.exit(cleanup2(dir))
v <- validate_config("demo", config_dir = dir)
expect_true(v$valid)
expect_equal(sev_of(v, "fwf_widths"), "warning")
expect_match(msgs_of(v, "fwf_widths"), "sum \\(8\\) exceeds the record length \\(6\\)")
dir2 <- vcfg2("AB12XY", format = "fwf", file_ext = ".txt",
                dataset = "fwf_widths: [2, 2]")
on.exit(cleanup2(dir2), add = TRUE)
v2 <- validate_config("demo", config_dir = dir2)
expect_true(v2$valid)
expect_equal(sev_of(v2, "fwf_widths"), "warning")
expect_match(msgs_of(v2, "fwf_widths"), "short of the record length \\(6\\)")
