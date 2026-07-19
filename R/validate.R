# validate_config(): the explicit guard that replaces the wizard's
# prevent-invalid-by-construction role for hand-edited YAML. Tier 1 (this
# file) needs nothing but the config files: vocabulary membership, value
# types/ranges, positional-list internal consistency, unresolved generator
# placeholders. The standalone call REPORTS every finding rather than aborting
# on the first, so one pass shows all problems; the in-run guard added to
# run_dq_check() later turns error-severity findings into typed aborts.

# -- reading a config file with typed failure classes --------------------------

# Reads one YAML config file, aborting with a distinct condition class per
# failure mode so callers (and tests) can tell them apart:
#   missing        -> dqcheckr_missing_file        (existing class)
#   empty          -> dqcheckr_empty_config
#   unparseable    -> dqcheckr_config_parse_error
#   not a key map  -> dqcheckr_invalid_config
.read_config_file <- function(path) {
  if (!file.exists(path))
    rlang::abort(paste0("Config file not found: ", path),
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))
  raw <- readLines(path, warn = FALSE)
  if (length(raw) == 0 || !any(nzchar(trimws(raw))))
    rlang::abort(paste0("Config file is empty: ", path),
                 class = c("dqcheckr_empty_config", "dqcheckr_error"))
  cfg <- tryCatch(
    yaml::read_yaml(path),
    error = function(e) rlang::abort(
      paste0("Config file could not be parsed as YAML: ", path, "\n  ",
             conditionMessage(e)),
      class = c("dqcheckr_config_parse_error", "dqcheckr_error"))
  )
  if (!is.list(cfg) || is.null(names(cfg)) || any(!nzchar(names(cfg))))
    rlang::abort(
      paste0("Config file must be a YAML map of keys to values: ", path),
      class = c("dqcheckr_invalid_config", "dqcheckr_error"))
  cfg
}

# -- findings ------------------------------------------------------------------

.vfinding <- function(file, key, severity, message) {
  data.frame(file = file, key = key, severity = severity, message = message,
             stringsAsFactors = FALSE)
}

.no_findings <- function() {
  data.frame(file = character(), key = character(), severity = character(),
             message = character(), stringsAsFactors = FALSE)
}

# Nearest known key for did-you-mean suggestions; NULL when nothing is close.
.suggest_key <- function(key, candidates) {
  d <- utils::adist(key, candidates, ignore.case = TRUE)
  if (min(d) <= 3) candidates[which.min(d)] else NULL
}

.unknown_key_msg <- function(key, candidates, where) {
  hint <- .suggest_key(key, candidates)
  paste0("Unknown key '", key, "' in ", where, ".",
         if (!is.null(hint)) paste0(" Did you mean '", hint, "'?") else "")
}

# -- scalar predicates ---------------------------------------------------------

.is_string  <- function(x) is.character(x) && length(x) == 1 && !is.na(x) && nzchar(x)
.is_count   <- function(x) is.numeric(x) && length(x) == 1 && !is.na(x) &&
  is.finite(x) && x >= 0 && x == floor(x)
.is_number  <- function(x) is.numeric(x) && length(x) == 1 && !is.na(x) && is.finite(x)
.is_frac    <- function(x) .is_number(x) && x >= 0 && x <= 1
.is_flag    <- function(x) is.logical(x) && length(x) == 1 && !is.na(x)
# YAML sequences arrive as an atomic vector (uniform) or a list; normalise.
.as_vec     <- function(x) if (is.list(x)) unlist(x, use.names = FALSE) else x
.is_str_vec <- function(x) {
  v <- .as_vec(x)
  is.character(v) && length(v) >= 1 && !anyNA(v) && all(nzchar(v))
}
.is_named_map <- function(x) is.list(x) && length(x) >= 1 &&
  !is.null(names(x)) && all(nzchar(names(x)))

# The generator's packed-FWF placeholder. Detected value-wise so a partially
# filled list ("TODO" left in one slot) is still caught.
.has_todo <- function(x) {
  v <- .as_vec(x)
  is.character(v) && any(toupper(trimws(v)) == "TODO")
}

# -- per-key type checkers -----------------------------------------------------

# One checker per vocabulary key: NULL when the value is acceptable, otherwise
# the message text for a finding. Keys whose deep structure is checked
# elsewhere in .validate_one_config (column_rules, rule maps) only get their
# container shape checked here. A completeness test asserts every vocabulary
# key has an entry.
.key_checkers <- list(
  dataset_name  = function(x) if (!.is_string(x)) "must be a non-empty string.",
  format        = function(x) {
    if (!.is_string(x) || !tolower(x) %in% c("csv", "fwf"))
      "must be \"csv\" or \"fwf\"."
  },
  encoding      = function(x) if (!.is_string(x)) "must be a non-empty string (an encoding name).",
  delimiter     = function(x) if (!.is_string(x) || nchar(x) != 1) "must be a single character.",
  quote_char    = function(x) if (!.is_string(x) || nchar(x) != 1) "must be a single character.",
  col_names     = function(x) {
    if (!.is_str_vec(x)) "must be a list of non-empty column names."
  },
  csv_skip      = function(x) if (!.is_count(x)) "must be an integer >= 0.",
  folder        = function(x) if (!.is_string(x)) "must be a directory path string.",
  current_file  = function(x) if (!.is_string(x)) "must be a file path string.",
  previous_file = function(x) if (!.is_string(x)) "must be a file path string.",
  fwf_widths    = function(x) {
    if (.has_todo(x)) return(NULL)  # handled as its own, clearer finding
    v <- .as_vec(x)
    if (!is.numeric(v) || length(v) < 1 || anyNA(v) ||
        any(v <= 0 | v != floor(v)))
      "must be a list of positive integers (one width per column)."
  },
  fwf_col_names = function(x) {
    if (!.is_str_vec(x)) "must be a list of non-empty column names."
  },
  fwf_skip      = function(x) if (!.is_count(x)) "must be an integer >= 0.",
  expected_columns = function(x) {
    if (!.is_str_vec(x)) "must be a list of column names."
  },
  key_columns   = function(x) if (!.is_str_vec(x)) "must be a list of column names.",
  column_types  = function(x) {
    if (!.is_named_map(x))
      return("must be a map of column name to type.")
    bad <- setdiff(unlist(x, use.names = FALSE), c("character", "numeric", "date"))
    if (length(bad) > 0)
      paste0("has invalid type(s): ", paste(bad, collapse = ", "),
             ". Must be one of: character, numeric, date.")
  },
  column_rules  = function(x) {
    if (!.is_named_map(x) || !all(vapply(x, is.list, logical(1))))
      "must be a map of column name to a map of rules."
  },
  rule_overrides = function(x) if (!.is_named_map(x)) "must be a map of rule name to value.",
  custom_checks_file = function(x) if (!.is_string(x)) "must be a file path string.",
  snapshot_db   = function(x) if (!.is_string(x)) "must be a file path string.",
  report_output_dir = function(x) if (!.is_string(x)) "must be a directory path string.",
  default_rules = function(x) if (!.is_named_map(x)) "must be a map of rule name to value."
)

# One checker per rule-vocabulary key (used for default_rules, rule_overrides,
# and column_rules entries alike).
.rule_checkers <- list(
  max_missing_rate               = function(x) if (!.is_frac(x))   "must be a number in [0, 1].",
  max_non_numeric_rate           = function(x) if (!.is_frac(x))   "must be a number in [0, 1].",
  warn_non_numeric_rate          = function(x) if (!.is_frac(x))   "must be a number in [0, 1].",
  max_z_score                    = function(x) if (!.is_number(x) || x <= 0) "must be a positive number.",
  iqr_fence_multiplier           = function(x) if (!.is_number(x) || x <= 0) "must be a positive number.",
  min_row_count                  = function(x) if (!.is_count(x))  "must be an integer >= 0.",
  max_row_count                  = function(x) if (!.is_count(x))  "must be an integer >= 0.",
  max_file_size_mb               = function(x) if (!.is_number(x) || x <= 0) "must be a positive number.",
  max_row_count_change_pct       = function(x) if (!.is_frac(x))   "must be a fraction in [0, 1].",
  max_missing_rate_change_pp     = function(x) if (!.is_number(x) || x < 0) "must be a number >= 0 (percentage points).",
  max_numeric_mean_shift_pct     = function(x) if (!.is_frac(x))   "must be a fraction in [0, 1] (e.g. 0.2 for 20%).",
  max_non_numeric_rate_change_pp = function(x) if (!.is_number(x) || x < 0) "must be a number >= 0 (percentage points).",
  type_inference_threshold       = function(x) if (!.is_frac(x) || x == 0) "must be a number in (0, 1].",
  flag_new_columns               = function(x) if (!.is_flag(x))   "must be true or false.",
  flag_dropped_columns           = function(x) if (!.is_flag(x))   "must be true or false.",
  flag_type_changes              = function(x) if (!.is_flag(x))   "must be true or false.",
  flag_column_order_change       = function(x) if (!.is_flag(x))   "must be true or false.",
  column_order_severity          = function(x) {
    if (!.is_string(x) || !tolower(x) %in% c("pass", "warn", "fail", "info"))
      "must be one of: pass, warn, fail, info."
  },
  missing_rate_change_severity   = function(x) {
    if (!.is_string(x) || !tolower(x) %in% c("warn", "fail"))
      "must be one of: warn, fail."
  },
  allowed_values                 = function(x) {
    v <- .as_vec(x)
    if (length(v) < 1 || anyNA(v)) "must be a non-empty list of values."
  },
  pattern                        = function(x) {
    if (!.is_string(x)) return("must be a regular-expression string.")
    ok <- tryCatch({ grepl(x, "probe", perl = TRUE); TRUE },
                   error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) "is not a valid regular expression."
  },
  min_value                      = function(x) if (!.is_number(x)) "must be a number.",
  max_value                      = function(x) if (!.is_number(x)) "must be a number."
)

# -- validating one rule map ---------------------------------------------------

# Shared by default_rules, rule_overrides (placement rules/both) and each
# column_rules entry (placement column/both). `where` names the location for
# messages, e.g. "default_rules" or "column_rules for column 'id'".
.validate_rule_map <- function(rules, placement_ok, file, where) {
  if (!.is_named_map(rules)) return(.no_findings())
  rv       <- .rule_vocabulary()
  allowed  <- rv$key[rv$placement %in% placement_ok]
  findings <- lapply(names(rules), function(k) {
    if (!k %in% rv$key)
      return(.vfinding(file, k, "warning", .unknown_key_msg(k, rv$key, where)))
    if (!k %in% allowed)
      return(.vfinding(file, k, "error",
                       paste0("Rule '", k, "' is not valid in ", where, ".")))
    msg <- .rule_checkers[[k]](rules[[k]])
    if (!is.null(msg))
      return(.vfinding(file, k, "error", paste0("Rule '", k, "' in ", where, " ", msg)))
    NULL
  })
  do.call(rbind, c(list(.no_findings()), .compact(findings)))
}

# -- validating one config file ------------------------------------------------

# scope: "dataset" or "global". dataset_name: the expected identity (dataset
# scope only). Returns a findings frame; never aborts.
.validate_one_config <- function(cfg, scope, file, dataset_name = NULL) {
  vocab    <- .config_vocabulary()
  in_scope <- vocab$key[vocab$scope %in% c(scope, "both")]
  findings <- list()
  add <- function(f) findings[[length(findings) + 1]] <<- f

  for (k in names(cfg)) {
    if (!k %in% vocab$key) {
      # Unknown everywhere: tolerated with a warning (hand-kept custom keys and
      # GUI-era extras round-trip; they just do nothing).
      add(.vfinding(file, k, "warning",
                    .unknown_key_msg(k, vocab$key, paste0("the ", scope, " config"))))
      next
    }
    if (!k %in% in_scope) {
      add(.vfinding(file, k, "warning",
                    paste0("Key '", k, "' is a ", setdiff(vocab$scope[vocab$key == k], "both"),
                           "-scope key and has no effect in the ", scope, " config.")))
      next
    }
    msg <- .key_checkers[[k]](cfg[[k]])
    if (!is.null(msg)) add(.vfinding(file, k, "error", paste0("'", k, "' ", msg)))
  }

  # Rule maps, wherever they are valid in this scope.
  if (scope == "global")
    add(.validate_rule_map(cfg[["default_rules"]], c("rules", "both"),
                           file, "default_rules"))
  if (scope == "dataset") {
    add(.validate_rule_map(cfg[["rule_overrides"]], c("rules", "both"),
                           file, "rule_overrides"))
    if (.is_named_map(cfg[["column_rules"]]))
      for (col in names(cfg[["column_rules"]]))
        add(.validate_rule_map(cfg[["column_rules"]][[col]], c("column", "both"),
                               file, paste0("column_rules for column '", col, "'")))
  }

  if (scope == "dataset") {
    fmt <- tolower(cfg[["format"]] %||% .default_read$format)

    # Identity: required present and matching the config filename -- the
    # "config folder is the dataset list" discipline. Warning severity: legacy
    # configs must keep running.
    if (is.null(cfg[["dataset_name"]]))
      add(.vfinding(file, "dataset_name", "warning",
                    "'dataset_name' is missing; it should be present and match the config filename."))
    else if (.is_string(cfg[["dataset_name"]]) && !is.null(dataset_name) &&
             !identical(cfg[["dataset_name"]], dataset_name))
      add(.vfinding(file, "dataset_name", "warning",
                    paste0("'dataset_name' is \"", cfg[["dataset_name"]],
                           "\" but the config file is for \"", dataset_name, "\".")))

    # File source: one of current_file / folder must be set.
    if (is.null(cfg[["current_file"]]) && is.null(cfg[["folder"]]))
      add(.vfinding(file, "current_file", "error",
                    "One of 'current_file' or 'folder' must be set."))
    else if (!is.null(cfg[["current_file"]]) && !is.null(cfg[["folder"]]))
      add(.vfinding(file, "folder", "note",
                    "Both 'current_file' and 'folder' are set; 'current_file' takes precedence."))

    # FWF structure.
    if (fmt == "fwf" && is.null(cfg[["fwf_widths"]]))
      add(.vfinding(file, "fwf_widths", "error",
                    "'fwf_widths' is required when format is \"fwf\"."))
    if (.has_todo(cfg[["fwf_widths"]]))
      add(.vfinding(file, "fwf_widths", "error",
                    paste0("'fwf_widths' still contains the generator's TODO placeholder. ",
                           "Fill in the column widths (see the ruler comment in the config) ",
                           "before running.")))
    if (!is.null(cfg[["fwf_widths"]]) && !is.null(cfg[["fwf_col_names"]]) &&
        !.has_todo(cfg[["fwf_widths"]])) {
      n_w <- length(.as_vec(cfg[["fwf_widths"]]))
      n_n <- length(.as_vec(cfg[["fwf_col_names"]]))
      if (n_w != n_n)
        add(.vfinding(file, "fwf_col_names", "error",
                      sprintf(paste0("'fwf_col_names' has %d name(s) but 'fwf_widths' has %d ",
                                     "width(s). Positional lists must match entry-for-entry -- ",
                                     "was an entry commented out?"), n_n, n_w)))
    }

    # Duplicate output names in positional lists: every downstream rule is
    # keyed by name, so duplicates make rules ambiguous.
    for (k in c("col_names", "fwf_col_names")) {
      v <- .as_vec(cfg[[k]])
      if (is.character(v) && anyDuplicated(v))
        add(.vfinding(file, k, "error",
                      paste0("'", k, "' contains duplicate name(s): ",
                             paste(unique(v[duplicated(v)]), collapse = ", "),
                             ". Output column names must be unique.")))
    }
  }

  do.call(rbind, c(list(.no_findings()), .compact(findings)))
}

# -- public API ----------------------------------------------------------------

#' Validate a dataset's configuration
#'
#' Checks the global \code{dqcheckr.yml} and the dataset's YAML against the
#' config vocabulary: unknown keys (with a did-you-mean suggestion), value
#' types and ranges, rule placement (rules-level vs per-column), positional-list
#' consistency (\code{fwf_col_names} vs \code{fwf_widths} lengths, duplicate
#' column names), unresolved generator \code{TODO} placeholders, and the
#' presence of a file source. All findings are collected and returned in one
#' pass -- nothing aborts on the first problem -- so a hand-edited config can
#' be fixed in one round trip.
#'
#' This is the config-only tier: it reads nothing but the two YAML files.
#' Findings have three severities: \code{"error"} (the run would misbehave or
#' abort), \code{"warning"} (suspicious but survivable, e.g. an unknown key,
#' which is tolerated so hand-kept extra keys round-trip), and \code{"note"}
#' (informational).
#'
#' A config file that cannot be read at all aborts with a typed condition
#' rather than returning findings: \code{dqcheckr_missing_file},
#' \code{dqcheckr_empty_config}, \code{dqcheckr_config_parse_error}, or
#' \code{dqcheckr_invalid_config} (not a YAML key map).
#'
#' @param dataset_name Character. Dataset name; must match
#'   \code{<dataset_name>.yml} in \code{config_dir}.
#' @param config_dir Character. Path to the directory containing
#'   \code{dqcheckr.yml} and the dataset YAML file. Defaults to \code{"."}.
#'
#' @return An object of class \code{dqcheckr_validation}: a list with
#'   \code{dataset_name}, \code{config_dir}, \code{findings} (a data frame
#'   with columns \code{file}, \code{key}, \code{severity}, \code{message}),
#'   \code{tier} (\code{"config-only"}), and \code{valid} (\code{TRUE} when
#'   no error-severity findings exist).
#'
#' @examples
#' tmp <- gsub("\\\\", "/", tempdir())
#' writeLines('snapshot_db: "snap.sqlite"', file.path(tmp, "dqcheckr.yml"))
#' writeLines(c('dataset_name: "demo"', 'format: csv', 'current_file: "x.csv"'),
#'            file.path(tmp, "demo.yml"))
#' v <- validate_config("demo", config_dir = tmp)
#' v$valid
#'
#' @export
validate_config <- function(dataset_name, config_dir = ".") {
  global_path  <- file.path(config_dir, "dqcheckr.yml")
  dataset_path <- file.path(config_dir, paste0(dataset_name, ".yml"))

  global_cfg  <- .read_config_file(global_path)
  dataset_cfg <- .read_config_file(dataset_path)

  findings <- rbind(
    .validate_one_config(global_cfg,  "global",  basename(global_path)),
    .validate_one_config(dataset_cfg, "dataset", basename(dataset_path),
                         dataset_name = dataset_name)
  )
  rownames(findings) <- NULL

  structure(
    list(dataset_name = dataset_name,
         config_dir   = config_dir,
         findings     = findings,
         tier         = "config-only",
         valid        = !any(findings$severity == "error")),
    class = "dqcheckr_validation"
  )
}

#' @export
print.dqcheckr_validation <- function(x, ...) {
  cat(sprintf("dqcheckr config validation: %s -- %s (tier: %s)\n",
              x$dataset_name, if (x$valid) "VALID" else "INVALID", x$tier))
  if (nrow(x$findings) == 0) {
    cat("No findings.\n")
  } else {
    for (i in seq_len(nrow(x$findings)))
      cat(sprintf("  [%s] %s: %s\n", x$findings$severity[i],
                  x$findings$file[i], x$findings$message[i]))
  }
  invisible(x)
}
