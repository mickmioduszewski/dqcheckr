# The config vocabulary: one internal source of truth for every YAML key the
# package consumes -- its scope, type, default, and whether it is positional.
# The validator checks configs against this table and the generators emit from
# it; without one shared table each would hard-code its own key list and the
# two would drift apart silently. Defaults are REFERENCED from the runtime
# constants (.default_read, .default_paths, .default_qc_rules,
# .default_comparison_rules in utils.R), never restated, so the vocabulary
# cannot disagree with what the code actually applies.

# One vocabulary row. `default` is wrapped in list() so any type (including
# NULL for "no default") fits a single list-column.
.vocab_row <- function(key, scope, type, required, positional, default,
                       description) {
  data.frame(key = key, scope = scope, type = type, required = required,
             positional = positional, has_default = !is.null(default),
             default = I(list(default)), description = description,
             stringsAsFactors = FALSE)
}

#' The top-level config-key vocabulary
#'
#' One row per YAML key valid at the top level of a dataset config or the
#' global \code{dqcheckr.yml}. Fields: \code{key}; \code{scope}
#' (\code{"dataset"}, \code{"global"}, or \code{"both"}); \code{type} (human
#' description of the expected YAML value); \code{required} (\code{"no"} or
#' \code{"conditional"} -- no key is unconditionally required); \code{positional}
#' (TRUE for lists read left-to-right against physical columns, which must
#' always be complete and are never candidates for commenting out);
#' \code{has_default}/\code{default}; \code{description}.
#' @keywords internal
#' @noRd
.config_vocabulary <- function() {
  rbind(
    .vocab_row("dataset_name", "dataset", "string", "no", FALSE, NULL,
      "Identity of the dataset. Written into every config by convention; dqcheckr itself takes the name as a function argument and matches it to the config filename."),
    .vocab_row("format", "dataset", "string: \"csv\" or \"fwf\"", "no", FALSE,
      .default_read$format,
      "File format of the delivery. Defaults to CSV; \"fwf\" switches to the fixed-width reader and makes fwf_widths required."),
    .vocab_row("encoding", "dataset", "string (iconv encoding name)", "no", FALSE,
      .default_read$encoding,
      "Text encoding of the delivery. ASCII and its aliases are read as UTF-8 (lossless superset); a declared UTF-8 is validity-scanned before parsing."),
    .vocab_row("delimiter", "dataset", "string (single character)", "no", FALSE,
      .default_read$delimiter,
      "Field separator for CSV files."),
    .vocab_row("quote_char", "dataset", "string (single character)", "no", FALSE,
      .default_read$quote_char,
      "Quote character for CSV files, passed through to the reader."),
    .vocab_row("col_names", "dataset", "list of strings (one per physical column)",
      "no", TRUE, NULL,
      "Explicit column names replacing the file's own header, in physical column order. Omit to use the file's header. POSITIONAL: always list every column; pair with csv_skip: 1 when the file has a header row being replaced."),
    .vocab_row("csv_skip", "dataset", "integer >= 0", "no", FALSE,
      .default_read$csv_skip,
      "Leading lines to drop from a CSV before reading, e.g. the original header row when col_names supplies replacement names."),
    .vocab_row("folder", "dataset", "string (directory path)", "conditional", FALSE, NULL,
      "Directory holding the deliveries; the two most recently modified files become current and previous. Required unless current_file is set."),
    .vocab_row("current_file", "dataset", "string (file path)", "conditional", FALSE, NULL,
      "Explicit path to the current delivery. Required unless folder is set; takes precedence over folder."),
    .vocab_row("previous_file", "dataset", "string (file path)", "no", FALSE, NULL,
      "Explicit path to the previous delivery for comparison checks. Only honoured alongside current_file."),
    .vocab_row("fwf_widths", "dataset", "list of integers (one per column)",
      "conditional", TRUE, NULL,
      "Column widths for fixed-width files, in physical order. Required when format is \"fwf\". POSITIONAL: always list every column; never comment out an entry."),
    .vocab_row("fwf_col_names", "dataset", "list of strings (one per column)",
      "no", TRUE, NULL,
      "Column names for fixed-width files, matching fwf_widths entry-for-entry. POSITIONAL."),
    .vocab_row("fwf_skip", "dataset", "integer >= 0", "no", FALSE,
      .default_read$fwf_skip,
      "Leading lines to drop from a fixed-width file before reading."),
    .vocab_row("expected_columns", "dataset", "list of column names", "no", FALSE, NULL,
      "Columns the delivery is expected to contain; missing or unexpected columns are flagged. Name-keyed: commenting an entry out safely drops that column from the expectation."),
    .vocab_row("key_columns", "dataset", "list of column names", "no", FALSE, NULL,
      "Columns forming the row identity, checked for uniqueness and missingness."),
    .vocab_row("column_types", "dataset", "map: column name -> type", "no", FALSE, NULL,
      "Per-column type pins (character, numeric, or date) overriding type inference."),
    .vocab_row("column_rules", "dataset", "map: column name -> rule map", "no", FALSE, NULL,
      "Per-column quality rules; see the rule vocabulary for the keys valid inside each column's map."),
    .vocab_row("rule_overrides", "dataset", "map: rule name -> value", "no", FALSE, NULL,
      "Dataset-level overrides merged over the global default_rules; see the rule vocabulary."),
    .vocab_row("custom_checks_file", "dataset", "string (file path)", "no", FALSE, NULL,
      "Path to a user-supplied R file of custom check functions run after the built-in checks."),
    .vocab_row("snapshot_db", "both", "string (file path)", "no", FALSE,
      .default_paths$snapshot_db,
      "SQLite snapshot database recording every run. Dataset value overrides the global one; relative paths resolve against the working directory."),
    .vocab_row("report_output_dir", "both", "string (directory path)", "no", FALSE,
      .default_paths$report_output_dir,
      "Directory receiving rendered HTML reports. Dataset value overrides the global one; relative paths resolve against the working directory."),
    .vocab_row("default_rules", "global", "map: rule name -> value", "no", FALSE, NULL,
      "Deployment-wide rule defaults, overridable per dataset via rule_overrides; see the rule vocabulary.")
  )
}

# One rule-vocabulary row. `placement` says where the key may appear:
# "rules"  -- global default_rules / dataset rule_overrides only;
# "column" -- inside a column_rules entry only;
# "both"   -- either level, with the column value winning for its column.
.rule_row <- function(key, placement, type, default, description) {
  data.frame(key = key, placement = placement, type = type,
             has_default = !is.null(default), default = I(list(default)),
             description = description, stringsAsFactors = FALSE)
}

#' The rule-key vocabulary
#'
#' One row per key valid inside \code{default_rules}/\code{rule_overrides}
#' and/or a \code{column_rules} entry. Keys with no default are checks or
#' behaviours that simply do not run when the key is absent.
#' @keywords internal
#' @noRd
.rule_vocabulary <- function() {
  rbind(
    # -- thresholds honoured at both levels (column value wins for its column)
    .rule_row("max_missing_rate", "both", "number in [0, 1]",
      .default_qc_rules$max_missing_rate,
      "Maximum tolerated missing-value rate per column before QC-01 fails."),
    .rule_row("max_non_numeric_rate", "both", "number in [0, 1]",
      .default_qc_rules$max_non_numeric_rate,
      "Maximum rate of unparseable values in a numeric column before the type check fails."),
    .rule_row("warn_non_numeric_rate", "both", "number in [0, 1]",
      .default_qc_rules$warn_non_numeric_rate,
      "Non-numeric rate above which the type check warns (below the fail threshold)."),
    .rule_row("max_z_score", "both", "positive number", NULL,
      "Z-score beyond which numeric values count as outliers. Unset: z-score outlier flagging is off."),
    .rule_row("iqr_fence_multiplier", "both", "positive number", NULL,
      "IQR fence multiplier for outlier flagging. Unset: IQR outlier flagging is off."),
    # -- table-level thresholds (rules only)
    .rule_row("min_row_count", "rules", "integer >= 0",
      .default_qc_rules$min_row_count,
      "Minimum acceptable row count for a delivery."),
    .rule_row("max_row_count", "rules", "integer >= 0", NULL,
      "Maximum acceptable row count. Unset: no upper bound is checked."),
    .rule_row("max_file_size_mb", "rules", "positive number", NULL,
      "Maximum acceptable file size in megabytes. Unset: file size is not checked."),
    # -- comparison thresholds (rules only; defaults from .default_comparison_rules)
    .rule_row("max_row_count_change_pct", "rules", "number in [0, 1] (fraction)",
      .default_comparison_rules$max_row_count_change_pct,
      "Maximum tolerated row-count change vs the previous delivery, as a fraction."),
    .rule_row("max_missing_rate_change_pp", "rules", "number (percentage points)",
      .default_comparison_rules$max_missing_rate_change_pp,
      "Maximum tolerated per-column missing-rate change vs previous, in percentage points."),
    .rule_row("max_numeric_mean_shift_pct", "both", "number in [0, 1] (fraction)",
      .default_comparison_rules$max_numeric_mean_shift_pct,
      "Maximum tolerated shift of a numeric column's mean vs previous, as a fraction. Per-column value in column_rules wins over the rules-level one."),
    .rule_row("max_non_numeric_rate_change_pp", "rules", "number (percentage points)",
      .default_comparison_rules$max_non_numeric_rate_change_pp,
      "Maximum tolerated per-column non-numeric-rate change vs previous, in percentage points."),
    # -- behaviour switches (rules only)
    .rule_row("type_inference_threshold", "rules", "number in (0, 1]",
      .default_qc_rules$type_inference_threshold,
      "Minimum proportion of values that must parse as numeric for a column to classify as numeric."),
    .rule_row("flag_new_columns", "rules", "logical",
      .default_qc_rules$flag_new_columns,
      "Whether columns new vs the previous delivery are flagged."),
    .rule_row("flag_dropped_columns", "rules", "logical",
      .default_qc_rules$flag_dropped_columns,
      "Whether columns dropped vs the previous delivery are flagged."),
    .rule_row("flag_type_changes", "rules", "logical",
      .default_qc_rules$flag_type_changes,
      "Whether inferred-type changes vs the previous delivery are flagged."),
    .rule_row("flag_column_order_change", "rules", "logical",
      .default_qc_rules$flag_column_order_change,
      "Whether a change in column order vs the previous delivery is flagged."),
    .rule_row("column_order_severity", "rules",
      "string: pass, warn, fail, or info", NULL,
      "Severity assigned to a column-order change. Unset: the check's built-in severity applies."),
    .rule_row("missing_rate_change_severity", "rules", "string: warn or fail",
      .default_qc_rules$missing_rate_change_severity,
      "Severity assigned when a missing-rate change exceeds its threshold."),
    # -- per-column-only rules (column_rules entries)
    .rule_row("allowed_values", "column", "list of allowed values", NULL,
      "Closed set of permitted values for the column; anything else fails."),
    .rule_row("pattern", "column", "string (PCRE regular expression)", NULL,
      "Regex every non-empty value must match."),
    .rule_row("min_value", "column", "number", NULL,
      "Lower bound for a numeric column."),
    .rule_row("max_value", "column", "number", NULL,
      "Upper bound for a numeric column.")
  )
}

#' Keys that are positional lists
#'
#' The lists read left-to-right against physical columns. They must always be
#' emitted complete by the generators and never commented out entry-wise: a
#' removed slot silently shifts every later column. The validator hard-fails
#' on length mismatches for exactly these keys.
#' @keywords internal
#' @noRd
.positional_keys <- function() {
  v <- .config_vocabulary()
  v$key[v$positional]
}
