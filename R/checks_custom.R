#' Run organisation-specific custom checks
#'
#' Sources the R file specified by \code{config$custom_checks_file}, which must
#' define a function \code{custom_checks(df)} returning a list of
#' \code{\link{dq_result}} objects. Returns an empty list if
#' \code{custom_checks_file} is not set in the config.
#'
#' The file is sourced into an isolated environment whose parent is
#' \code{baseenv()}, so only base R functions are available by default.
#' \code{\link{dq_result}} is explicitly injected and can be called without
#' qualification. All other dqcheckr exports (e.g. \code{resolve_col_type},
#' \code{infer_col_type}) must be qualified: \code{dqcheckr::resolve_col_type()}.
#' Any error -- missing file, undefined function, runtime failure, or a
#' malformed result element (each element must have the seven
#' \code{\link{dq_result}} fields and a valid status) -- stops the run with a
#' clear message.
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
  path <- config[["custom_checks_file"]]
  if (is.null(path)) return(list())

  if (!file.exists(path)) {
    rlang::abort(paste0("Custom checks file not found: ", path),
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))
  }

  env <- new.env(parent = baseenv())
  env$dq_result <- dq_result
  tryCatch(
    source(path, local = env),
    error = function(e)
      rlang::abort(paste0("Failed to source custom checks file '", path, "': ",
                          conditionMessage(e)),
                   class = c("dqcheckr_parse_error", "dqcheckr_error"))
  )

  if (!exists("custom_checks", envir = env, inherits = FALSE)) {
    rlang::abort(paste0("custom_checks() function not defined in: ", path),
                 class = c("dqcheckr_invalid_custom_checks", "dqcheckr_error"))
  }

  results <- tryCatch(
    env$custom_checks(df),
    error = function(e)
      rlang::abort(paste0("custom_checks() runtime error: ", conditionMessage(e)),
                   class = c("dqcheckr_custom_check_runtime_error", "dqcheckr_error"))
  )

  if (!is.list(results)) {
    rlang::abort(paste0("custom_checks() must return a list of dq_result objects, got: ",
                        class(results)),
                 class = c("dqcheckr_invalid_custom_checks", "dqcheckr_error"))
  }

  # Validate each element at this boundary -- where the check author can act
  # on the message. Malformed results would otherwise fail much later inside
  # overall_status() or the snapshot writer with misleading errors.
  required_fields <- c("check_id", "check_name", "column", "status",
                       "observed", "threshold", "message")
  valid_statuses  <- c("PASS", "WARN", "FAIL", "INFO")
  for (i in seq_along(results)) {
    r <- results[[i]]
    if (!is.list(r) || !all(required_fields %in% names(r))) {
      rlang::abort(sprintf(
        paste0("custom_checks() result %d is not a dq_result object. Each ",
               "element must be a named list with fields: %s. Build results ",
               "with dq_result()."),
        i, paste(required_fields, collapse = ", ")),
        class = c("dqcheckr_invalid_custom_checks", "dqcheckr_error"))
    }
    if (!is.character(r$status) || length(r$status) != 1 ||
        !r$status %in% valid_statuses) {
      rlang::abort(sprintf(
        "custom_checks() result %d has invalid status (%s). Must be one of: %s.",
        i, paste(deparse(r$status), collapse = ""),
        paste(valid_statuses, collapse = ", ")),
        class = c("dqcheckr_invalid_custom_checks", "dqcheckr_error"))
    }
  }

  results
}
