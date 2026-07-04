# run_custom_checks(): boundary validation of user-supplied results (0.2.3, B-08)

write_custom_file <- function(body) {
  path <- tempfile(fileext = ".R")
  writeLines(body, path)
  path
}

test_that("run_custom_checks() passes through well-formed results", {
  path <- write_custom_file(c(
    "custom_checks <- function(df) {",
    "  list(dq_result('CUST-01', 'row check', status = 'PASS',",
    "                 observed = as.character(nrow(df)), message = 'ok'))",
    "}"
  ))
  on.exit(unlink(path))
  cfg <- base_config(list(custom_checks_file = path))
  res <- run_custom_checks(make_accounts_df(), cfg)
  expect_length(res, 1)
  expect_equal(res[[1]]$status, "PASS")
})

test_that("run_custom_checks() rejects elements missing dq_result fields", {
  path <- write_custom_file(c(
    "custom_checks <- function(df) {",
    "  list(list(status = 'PASS'))",     # not a dq_result
    "}"
  ))
  on.exit(unlink(path))
  cfg <- base_config(list(custom_checks_file = path))
  expect_error(run_custom_checks(make_accounts_df(), cfg),
               class = "dqcheckr_invalid_custom_checks")
})

test_that("run_custom_checks() rejects elements with an invalid status", {
  path <- write_custom_file(c(
    "custom_checks <- function(df) {",
    "  r <- dq_result('CUST-01', 'x', status = 'PASS', observed = 'o', message = 'm')",
    "  r$status <- 'BROKEN'",
    "  list(r)",
    "}"
  ))
  on.exit(unlink(path))
  cfg <- base_config(list(custom_checks_file = path))
  expect_error(run_custom_checks(make_accounts_df(), cfg),
               class = "dqcheckr_invalid_custom_checks")
})

test_that("run_custom_checks() error names the offending element index", {
  path <- write_custom_file(c(
    "custom_checks <- function(df) {",
    "  ok <- dq_result('CUST-01', 'x', status = 'PASS', observed = 'o', message = 'm')",
    "  list(ok, list(bad = TRUE))",
    "}"
  ))
  on.exit(unlink(path))
  cfg <- base_config(list(custom_checks_file = path))
  expect_error(run_custom_checks(make_accounts_df(), cfg),
               regexp = "result 2")
})
