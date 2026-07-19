# validate_config(): the explicit guard that replaces the wizard's
# prevent-invalid-by-construction role for hand-edited YAML. Tier 1 (this
# file) needs nothing but the config files: vocabulary membership, value
# types/ranges, positional-list internal consistency, unresolved generator
# placeholders. The standalone call REPORTS every finding rather than aborting
# on the first, so one pass shows all problems; run_dq_check()'s in-run guard
# turns error-severity findings into typed aborts.

# -- reading a config file with typed failure classes --------------------------

# Reads one YAML config file, aborting with a distinct condition class per
# failure mode so callers (and tests) can tell them apart:
#   missing        -> dqcheckr_missing_file        (existing class)
#   empty          -> dqcheckr_empty_config
#   unparseable    -> dqcheckr_config_parse_error
#   not a key map  -> dqcheckr_invalid_config
# allow_empty: the GLOBAL config may legitimately be empty or comments-only --
# every key defaults, and load_config() has always tolerated it -- so it reads
# as an empty map rather than blocking every run in the deployment. A dataset
# config, by contrast, cannot run empty, so the strict aborts stand there.
.read_config_file <- function(path, allow_empty = FALSE) {
  if (!file.exists(path))
    rlang::abort(paste0("Config file not found: ", path),
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))
  raw <- readLines(path, warn = FALSE)
  if (length(raw) == 0 || !any(nzchar(trimws(raw)))) {
    if (allow_empty) return(structure(list(), empty_config = TRUE))
    rlang::abort(paste0("Config file is empty: ", path),
                 class = c("dqcheckr_empty_config", "dqcheckr_error"))
  }
  cfg <- tryCatch(
    yaml::read_yaml(path),
    error = function(e) rlang::abort(
      paste0("Config file could not be parsed as YAML: ", path, "\n  ",
             conditionMessage(e)),
      class = c("dqcheckr_config_parse_error", "dqcheckr_error"))
  )
  if (is.null(cfg) && allow_empty)          # comments-only: parses to NULL
    return(structure(list(), empty_config = TRUE))
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
# A checker message carrying warning (not error) severity.
.warn_msg   <- function(m) structure(m, severity = "warning")

# Format as a safe scalar for the STRUCTURAL checks. A malformed value (e.g.
# the YAML list `format: [csv, fwf]`) has already drawn its finding from the
# format checker; the structural checks must not crash on it (`fmt == "fwf"`
# with length 2 is a base R error), so they proceed as if the default.
.safe_format <- function(cfg) {
  f <- cfg[["format"]]
  if (.is_string(f) && tolower(f) %in% c("csv", "fwf")) tolower(f)
  else .default_read$format
}
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
  description   = function(x) if (!.is_string(x)) "must be a non-empty string.",
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
  # The two change-thresholds bound an UNBOUNDED relative change (a row count
  # can more than double; a mean can shift 300%), so values > 1 are legal and
  # deployed GUI-written configs carry them -- only negatives are errors. A
  # value > 5 is almost certainly a raw percentage (20 meaning 20%) that would
  # silently disable the check, so it draws a warning, not a block.
  max_row_count_change_pct       = function(x) {
    if (!.is_number(x) || x < 0)
      return("must be a number >= 0 (a fraction: 0.2 = 20%).")
    if (x > 5) .warn_msg("looks like a raw percentage -- fractions are expected (0.2 = 20%), so this value would tolerate almost any change.")
  },
  max_missing_rate_change_pp     = function(x) if (!.is_number(x) || x < 0) "must be a number >= 0 (percentage points).",
  max_numeric_mean_shift_pct     = function(x) {
    if (!.is_number(x) || x < 0)
      return("must be a number >= 0 (a fraction: 0.2 = 20%).")
    if (x > 5) .warn_msg("looks like a raw percentage -- fractions are expected (0.2 = 20%), so this value would tolerate almost any shift.")
  },
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
      return(.vfinding(file, k, attr(msg, "severity") %||% "error",
                       paste0("Rule '", k, "' in ", where, " ", msg)))
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
    if (!is.null(msg))
      # Honour .warn_msg() here exactly as the rule-checker site does: a
      # checker that downgrades must not silently escalate to a blocker.
      add(.vfinding(file, k, attr(msg, "severity") %||% "error",
                    paste0("'", k, "' ", msg)))
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
    fmt <- .safe_format(cfg)

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

# -- Tier 2: header-only cross-check against the delivery file -----------------

# Read the first n lines of a file honouring the config's encoding, with a
# UTF-8 BOM stripped. Bounded by construction: readLines(n) never touches the
# body of a multi-GB delivery.
.read_head_lines <- function(path, n, encoding) {
  con <- file(path, open = "r", encoding = encoding)
  on.exit(close(con), add = TRUE)
  lines <- readLines(con, n = n, warn = FALSE)
  if (length(lines) > 0) lines[1] <- sub("^\ufeff", "", lines[1])
  # A CRLF file read under an encoding that bypasses text-mode translation
  # leaves a trailing \r; strip so FWF record lengths are byte-honest.
  sub("\r$", "", lines)
}

# Byte length of the record after `skip` lines, read on a BINARY connection so
# no re-encoding happens: readLines on "rb" preserves each line's raw bytes
# (as-if latin1) and strips LF/CRLF/CR terminators itself, so
# nchar(type = "bytes") is the true on-disk record length -- with none of the
# chunk-boundary bookkeeping a hand-rolled scanner needs. A UTF-8 BOM is
# excluded from record 1. NA when the file has no such record. Only meaningful
# for UTF-8/single-byte encodings; the caller gates on .encoding_class().
.head_record_bytes <- function(path, skip) {
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  l <- suppressWarnings(readLines(con, n = skip + 1L))  # warns on missing final EOL
  if (length(l) < skip + 1L) return(NA_integer_)
  rec <- l[skip + 1L]
  if (skip == 0L) rec <- sub("^\xef\xbb\xbf", "", rec, useBytes = TRUE)
  nchar(rec, type = "bytes")
}

# Split one delimited line into fields, honouring the quote character.
# na.strings is emptied: scan()'s default turns a field spelled 'NA' into
# NA_character_, but a header/record field is text -- a column literally named
# NA must survive as the string "NA" (an NA here crashed the sniffer's rename
# comparison and drew spurious not-in-the-delivery warnings in Tier 2).
.split_fields <- function(line, delim, quote) {
  scan(text = line, what = character(), sep = delim, quote = quote,
       quiet = TRUE, strip.white = FALSE, blank.lines.skip = FALSE,
       na.strings = character(0))
}

# Columns-exist checks shared by CSV and FWF: `names` is the effective column
# set, or NULL when unknown (e.g. FWF without fwf_col_names) -- then nothing
# to check. ALL Tier-2 findings carry warning severity, never error: a
# cross-check against the delivery can fail because of delivery DRIFT (the
# supplier renames or drops a column), not only a config mistake, and drift
# must produce a recorded FAIL run (QC-12, the schema checks) with a snapshot
# and report -- not a pre-snapshot abort that leaves no history row. Only
# Tier-1 (config-only) errors block a run.
.tier2_name_findings <- function(cfg, names, file) {
  if (is.null(names)) return(.no_findings())
  findings <- list()
  add <- function(key, severity, what, missing)
    findings[[length(findings) + 1]] <<- .vfinding(
      file, key, severity,
      paste0("'", key, "' ", what, " column(s) not in the delivery: ",
             paste(missing, collapse = ", "), "."))
  miss <- function(x) setdiff(.as_vec(x), names)

  if (!is.null(cfg[["key_columns"]])) {
    m <- miss(cfg[["key_columns"]])
    if (length(m)) add("key_columns", "warning", "names", m)
  }
  if (!is.null(cfg[["expected_columns"]])) {
    m <- miss(cfg[["expected_columns"]])
    if (length(m)) add("expected_columns", "warning", "expects", m)
  }
  if (.is_named_map(cfg[["column_types"]])) {
    m <- setdiff(names(cfg[["column_types"]]), names)
    if (length(m)) add("column_types", "warning", "types", m)
  }
  if (.is_named_map(cfg[["column_rules"]])) {
    m <- setdiff(names(cfg[["column_rules"]]), names)
    if (length(m)) add("column_rules", "warning", "has rules for", m)
  }
  do.call(rbind, c(list(.no_findings()), findings))
}

# Runs the header-only cross-check. Returns list(findings=..., skipped=NULL)
# on success, or list(findings=empty, skipped="reason") when the delivery is
# not resolvable/readable -- skipping is a stated outcome, never silent.
.validate_tier2 <- function(cfg, file) {
  files <- tryCatch(detect_files(cfg), error = function(e) e)
  if (inherits(files, "error"))
    return(list(findings = .no_findings(), skipped = conditionMessage(files)))

  fmt <- .safe_format(cfg)
  enc <- normalise_encoding(cfg[["encoding"]] %||% .default_read$encoding)

  head_read <- tryCatch({
    if (fmt == "fwf") {
      skip  <- cfg[["fwf_skip"]] %||% .default_read$fwf_skip
      # The byte read below is the branch's ONLY file access: after the
      # bytes-vs-bytes rewrite, a decoded head read here had no remaining
      # consumer -- the name checks work from the config alone.
      rec_bytes <- .head_record_bytes(files$current, skip)
      if (is.na(rec_bytes)) stop("file has no data line to inspect")

      findings <- list()
      widths <- .as_vec(cfg[["fwf_widths"]])
      if (is.numeric(widths) && length(widths) > 0 && !anyNA(widths)) {
        total <- sum(widths)
        # The comparison is BYTES vs bytes: read_fwf slices records by byte
        # position, so measuring the decoded line in characters would flag a
        # multibyte UTF-8 delivery with perfectly correct widths on every
        # run. Only meaningful when bytes are the record's unit -- for
        # UTF-16/32-class encodings the raw scan would be garbage, so the
        # check is skipped rather than wrong. Both directions stay warnings
        # (Tier-2 policy): a record-length change can be delivery drift.
        if (.encoding_class(enc) != "other") {
          if (total > rec_bytes)
            findings <- c(findings, list(.vfinding(
              file, "fwf_widths", "warning",
              sprintf(paste0("'fwf_widths' sum (%d) exceeds the record length ",
                             "(%d bytes); trailing fields would be silently ",
                             "truncated or misaligned."), total, rec_bytes))))
          else if (total < rec_bytes)
            findings <- c(findings, list(.vfinding(
              file, "fwf_widths", "warning",
              sprintf("'fwf_widths' sum (%d) is short of the record length (%d bytes).",
                      total, rec_bytes))))
        }
      }
      eff_names <- if (!is.null(cfg[["fwf_col_names"]]))
        .as_vec(cfg[["fwf_col_names"]]) else NULL
      findings <- c(findings, list(.tier2_name_findings(cfg, eff_names, file)))
      do.call(rbind, c(list(.no_findings()), findings))
    } else {
      skip  <- cfg[["csv_skip"]] %||% .default_read$csv_skip
      lines <- .read_head_lines(files$current, skip + 1, enc)
      if (length(lines) < skip + 1) stop("file has no line to inspect after csv_skip")
      # After skipping, the first remaining line is the header (no col_names)
      # or the first data record (col_names supplied) -- its field count is
      # the physical column count either way.
      fields  <- .split_fields(lines[skip + 1],
                               cfg[["delimiter"]]  %||% .default_read$delimiter,
                               cfg[["quote_char"]] %||% .default_read$quote_char)
      n_file  <- length(fields)

      findings <- list()
      eff_names <- fields
      if (!is.null(cfg[["col_names"]])) {
        eff_names <- .as_vec(cfg[["col_names"]])
        if (length(eff_names) != n_file)
          findings <- c(findings, list(.vfinding(
            file, "col_names", "warning",
            sprintf(paste0("'col_names' has %d name(s) but the delivery has %d ",
                           "column(s). Positional lists must cover every physical ",
                           "column -- was an entry commented out, or has the ",
                           "delivery changed shape?"),
                    length(eff_names), n_file))))
      }
      findings <- c(findings, list(.tier2_name_findings(cfg, eff_names, file)))
      do.call(rbind, c(list(.no_findings()), findings))
    }
  }, error = function(e) e)

  if (inherits(head_read, "error"))
    return(list(findings = .no_findings(),
                skipped  = paste0("could not read the delivery header: ",
                                  conditionMessage(head_read))))
  list(findings = .clamp_tier2(head_read), skipped = NULL)
}

# STRUCTURAL clamp of the tier policy: no Tier-2 finding may block a run,
# whatever severity a future check hands in. Delivery-facing cross-checks can
# always mean drift, and drift must reach a recorded run. Named (not inlined)
# so the guard itself is testable against an error-severity frame.
.clamp_tier2 <- function(findings) {
  if (nrow(findings) > 0)
    findings$severity[findings$severity == "error"] <- "warning"
  findings
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
#' Validation runs in two tiers. \strong{Tier 1 (config-only)} reads nothing
#' but the two YAML files and always runs. \strong{Tier 2 (header cross-check)}
#' additionally opens just the first line(s) of the delivery the config points
#' at -- never the file body, so it is cheap even for multi-GB files on a
#' network share -- and verifies the config against reality:
#' \code{col_names} length vs the physical column count,
#' \code{key_columns}/\code{expected_columns}/\code{column_types}/
#' \code{column_rules} naming columns that exist, and \code{fwf_widths}
#' summing to the record length. When no delivery file is resolvable (config
#' written ahead of the first delivery, empty folder, unreadable header),
#' Tier 2 is skipped and the skip is \emph{stated} in the result
#' (\code{tier2_skipped}) and by \code{print()} -- a verdict always says
#' which tier it reached.
#'
#' Findings have three severities, split by one rule: \strong{config mistakes
#' are errors} (wrong types, broken positional lists, misplaced rule keys, a
#' missing file source — things only an edit can cause) and \strong{
#' delivery-facing findings are warnings} (a key column absent from the file,
#' a column-count mismatch — these can equally mean the supplier changed the
#' delivery, and drift must be recorded by a completed run, not abort it).
#' \code{"note"} is informational. Unknown keys warn, so hand-kept extra keys
#' round-trip. All Tier-2 findings are therefore warnings by construction.
#'
#' A \emph{dataset} config file that cannot be read at all aborts with a typed
#' condition rather than returning findings: \code{dqcheckr_missing_file},
#' \code{dqcheckr_empty_config}, \code{dqcheckr_config_parse_error}, or
#' \code{dqcheckr_invalid_config} (not a YAML key map). An empty or
#' comments-only \emph{global} \code{dqcheckr.yml} is tolerated as
#' all-defaults with a warning finding, matching how the package has always
#' run such deployments.
#'
#' @param dataset_name Character. Dataset name; must match
#'   \code{<dataset_name>.yml} in \code{config_dir}.
#' @param config_dir Character. Path to the directory containing
#'   \code{dqcheckr.yml} and the dataset YAML file. Defaults to \code{"."}.
#'
#' @return An object of class \code{dqcheckr_validation}: a list with
#'   \code{dataset_name}, \code{config_dir}, \code{findings} (a data frame
#'   with columns \code{file}, \code{key}, \code{severity}, \code{message}),
#'   \code{tier} (\code{"config+header"} when Tier 2 ran, else
#'   \code{"config-only"}), \code{tier2_skipped} (\code{NULL}, or the reason
#'   Tier 2 did not run), and \code{valid} (\code{TRUE} when no
#'   error-severity findings exist).
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

  global_cfg  <- .read_config_file(global_path, allow_empty = TRUE)
  dataset_cfg <- .read_config_file(dataset_path)

  # Defense in depth: the validator's contract is malformed-input-in,
  # findings-out -- it must NEVER itself crash on a value shape nobody
  # anticipated. Any internal error becomes an error-severity finding.
  guard <- function(expr, file) tryCatch(expr, error = function(e)
    .vfinding(file, "(validator)", "error",
              paste0("Internal validation error (please report): ",
                     conditionMessage(e))))

  findings <- rbind(
    if (isTRUE(attr(global_cfg, "empty_config")))
      .vfinding(basename(global_path), "(file)", "warning",
                "Global config is empty or comments-only; all defaults apply.")
    else .no_findings(),
    guard(.validate_one_config(global_cfg,  "global",  basename(global_path)),
          basename(global_path)),
    guard(.validate_one_config(dataset_cfg, "dataset", basename(dataset_path),
                               dataset_name = dataset_name),
          basename(dataset_path))
  )

  tier2 <- tryCatch(.validate_tier2(dataset_cfg, basename(dataset_path)),
                    error = function(e) list(
                      findings = .no_findings(),
                      skipped  = paste0("internal error during the header ",
                                        "cross-check: ", conditionMessage(e))))
  findings <- rbind(findings, tier2$findings)
  rownames(findings) <- NULL

  structure(
    list(dataset_name  = dataset_name,
         config_dir    = config_dir,
         findings      = findings,
         tier          = if (is.null(tier2$skipped)) "config+header" else "config-only",
         tier2_skipped = tier2$skipped,
         valid         = !any(findings$severity == "error")),
    class = "dqcheckr_validation"
  )
}

#' @export
print.dqcheckr_validation <- function(x, ...) {
  cat(sprintf("dqcheckr config validation: %s -- %s (tier: %s)\n",
              x$dataset_name, if (x$valid) "VALID" else "INVALID", x$tier))
  if (!is.null(x$tier2_skipped))
    cat(sprintf("  Header cross-check skipped: %s\n", x$tier2_skipped))
  if (nrow(x$findings) == 0) {
    cat("No findings.\n")
  } else {
    for (i in seq_len(nrow(x$findings)))
      cat(sprintf("  [%s] %s: %s\n", x$findings$severity[i],
                  x$findings$file[i], x$findings$message[i]))
  }
  invisible(x)
}
