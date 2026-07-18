
# Tests that render_report() only writes to the configured output_dir
# (never to the working directory or the package template directory).

make_render_env <- function() {
  tmp <- withr::local_tempdir()
  dat <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
  cfg <- list(
    format   = "csv",
    encoding = "UTF-8",
    rules    = list(max_missing_rate = 0.60, max_non_numeric_rate = 0.50,
                    min_row_count = 0, type_inference_threshold = 0.90),
    column_rules     = list(),
    column_types     = list(),
    key_columns      = NULL,
    expected_columns = NULL
  )
  df <- readr::read_delim(dat, delim = ",", col_types = readr::cols(.default = "c"),
                          show_col_types = FALSE)
  df <- as.data.frame(lapply(df, trimws), stringsAsFactors = FALSE)
  list(tmp = tmp, cfg = cfg, df = df)
}

test_that("render_report() returns NULL with a warning when Quarto is unavailable", {
  skip_if(quarto::quarto_available(), "skipped: Quarto is available on this system")
  env <- make_render_env()
  expect_warning(
    result <- render_report(
      dataset_name = "test", file_name = "f.csv", file_path = tempfile(),
      df = env$df, qc_results = list(), cp_results = list(),
      custom_results = list(), snapshot_history = NULL,
      config = env$cfg, output_dir = env$tmp, open_report = FALSE
    ),
    regexp = "Quarto"
  )
  expect_null(result)
})

test_that("render_report() writes output only to output_dir, not CWD", {
  skip_on_cran()  # renders via Quarto when available -- keep CRAN wall time bounded
  skip_if_not(quarto::quarto_available(), "Quarto CLI not available")
  env   <- make_render_env()
  before_cwd <- list.files(getwd(), pattern = "\\.html$")

  result <- render_report(
    dataset_name = "test", file_name = "f.csv",
    file_path = system.file("demonstrations/data/starwars.csv", package = "dqcheckr"),
    df = env$df, qc_results = list(), cp_results = list(),
    custom_results = list(), snapshot_history = NULL,
    config = env$cfg, output_dir = env$tmp, open_report = FALSE
  )

  after_cwd <- list.files(getwd(), pattern = "\\.html$")
  expect_equal(before_cwd, after_cwd)  # no new HTML in CWD

  expect_false(is.null(result))
  expect_true(file.exists(result))
  expect_true(startsWith(normalizePath(result),
                         normalizePath(env$tmp)))
})

test_that("render_report() errors when Quarto writes no output file (B-09)", {
  # Quarto 'available' but its render leaves no file behind -- the guard that
  # stops render_report() naming a report that does not exist (and letting
  # run_dq_check() record the run as a success). Mirrors the drift writer's
  # equivalent guard test.
  env <- make_render_env()
  testthat::local_mocked_bindings(
    quarto_available = function(...) TRUE,
    quarto_render    = function(...) invisible(NULL),
    .package = "quarto")
  expect_error(
    render_report(
      dataset_name = "test", file_name = "f.csv", file_path = tempfile(),
      df = env$df, qc_results = list(), cp_results = list(),
      custom_results = list(), snapshot_history = NULL,
      config = env$cfg, output_dir = env$tmp, open_report = FALSE
    ),
    class = "dqcheckr_render_error"
  )
})

test_that("render_report() output filename contains dataset_name", {
  skip_on_cran()  # renders via Quarto when available -- keep CRAN wall time bounded
  skip_if_not(quarto::quarto_available(), "Quarto CLI not available")
  env    <- make_render_env()
  result <- render_report(
    dataset_name = "myds", file_name = "f.csv",
    file_path = system.file("demonstrations/data/starwars.csv", package = "dqcheckr"),
    df = env$df, qc_results = list(), cp_results = list(),
    custom_results = list(), snapshot_history = NULL,
    config = env$cfg, output_dir = env$tmp, open_report = FALSE
  )
  expect_match(basename(result), "^myds_")
})
