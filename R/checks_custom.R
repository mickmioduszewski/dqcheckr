#' Run organisation-specific custom checks
#'
#' Sources the R file specified by \code{config$custom_checks_file}, which must
#' define a function \code{custom_checks(df)} returning a list of
#' \code{\link{dq_result}} objects. Returns an empty list if
#' \code{custom_checks_file} is not set in the config.
#'
#' @param df A data frame. The current delivery.
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A list of \code{\link{dq_result}} objects (may be empty).
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg     <- load_config("starwars_csv", config_dir = cfg_dir)
#' path    <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df      <- read_dataset(path, cfg)
#' results <- run_custom_checks(df, cfg)
#'
#' @export
run_custom_checks <- function(df, config) {
  path <- config$custom_checks_file
  if (is.null(path)) return(list())

  if (!file.exists(path)) {
    rlang::abort(paste0("Custom checks file not found: ", path))
  }

  env <- new.env(parent = baseenv())
  env$dq_result <- dq_result
  tryCatch(
    source(path, local = env),
    error = function(e)
      rlang::abort(paste0("Failed to source custom checks file '", path, "': ",
                          conditionMessage(e)))
  )

  if (!exists("custom_checks", envir = env, inherits = FALSE)) {
    rlang::abort(paste0("custom_checks() function not defined in: ", path))
  }

  results <- tryCatch(
    env$custom_checks(df),
    error = function(e)
      rlang::abort(paste0("custom_checks() runtime error: ", conditionMessage(e)))
  )

  if (!is.list(results)) {
    rlang::abort(paste0("custom_checks() must return a list of dq_result objects, got: ",
                        class(results)))
  }

  results
}
