# dqcheckr (development version)

## Bug fixes

* Column type inference no longer misclassifies a value whose *prefix* happens
  to be a date. `as.Date()` matches a prefix and silently ignores trailing
  characters, so `"2024-01-15x"` and the 9-digit id `"202401159"` (whose first
  eight digits parse under `%Y%m%d`) were both classified as `"date"` — which
  made corrupt dates pass QC-06 and stripped the numeric checks (QC-07/08/11)
  from id columns of eight or more digits. Each date format is now gated on an
  anchored shape before calendar validation. The documented caveat is
  unchanged: a genuine eight-digit value that is also a valid `%Y%m%d` date
  still classifies as a date; a nine-digit id now correctly classifies as
  numeric.
* `read_recent_snapshots()` now returns the full set of columns even for a
  snapshot database created before 0.2.3. Previously it ran `SELECT *` without
  migrating, so an older database returned rows with the newer columns (such as
  `report_file`) *absent* rather than `NA`, and callers relying on those
  columns errored instead of degrading. The missing columns are now filled in
  after the read with the same defaults a migration would apply; the database
  file itself is not modified, so reads remain safe on read-only or
  network-shared databases.

## Packaging

* The bundled `starwars_csv` demonstration data (`inst/demonstrations/data/`)
  is now shipped. An unanchored `.gitignore` rule had excluded it, so a fresh
  clone was missing the file that 27 example blocks and two tests depend on,
  and `R CMD check` failed on a clean checkout.
* The fixed-width demonstration (`starwars_fwf`) now has its data file. A new
  `inst/demonstrations/makedata.R` derives `starwars.fwf` from the CSV, so the
  FWF half of `demo.R` runs end-to-end instead of aborting on a missing file.

# dqcheckr 0.2.4

## Bug fixes

* A declared `encoding` of ASCII (or a formal alias such as `US-ASCII`) is now
  read as UTF-8. ASCII is a strict subset of UTF-8, so this is lossless — and
  it removes a hard R session crash ("Invalid multibyte sequence" inside
  vroom/iconv, not a catchable R error) when a delivery declared ASCII
  contains a byte above 127 beyond whatever sample an encoding sniffer
  originally looked at.

## New features

* New QC-16 "File encoding" check. When the effective encoding is UTF-8,
  `read_dataset()` now validity-scans the entire file before parsing. A
  delivery that is not valid UTF-8 no longer risks crashing or silently
  producing mojibake: it is read with a single-byte fallback encoding, the
  run completes, and QC-16 reports a FAIL naming the detector's best guess at
  the actual encoding (suppliers can change export encodings between
  deliveries, so this is checked per delivery). Valid files and declared
  single-byte encodings (which have no invalid byte sequences) report PASS.
  New dependency: `stringi`.

# dqcheckr 0.2.3

## Bug fixes

* A delivery with zero data rows (e.g. a header-only CSV) no longer aborts
  `run_dq_check()` with an untyped "missing value where TRUE/FALSE needed"
  error. Missing rates are defined as 0 for empty inputs, and QC-14 gains an
  unconditional "Empty file" FAIL sub-check so an empty delivery always fails
  the run — with a snapshot and report — instead of crashing it.
* CP-04 (numeric mean shift) no longer errors when a numeric column has no
  parseable values in the current delivery; it now emits a WARN result saying
  the mean shift cannot be computed.
* `detect_files()` no longer considers subdirectories of `folder` when
  picking the current/previous file by modification time.
* `dq_result(threshold = NULL)` now yields an `NA` threshold instead of
  failing with "argument is of length zero"; invalid vector `status` values
  produce a clear typed error.
* An invalid regex in a `column_rules` `pattern` now produces a QC-13 FAIL
  result naming the pattern instead of aborting the run; an invalid
  `column_order_severity` is rejected at `load_config()` time with a typed
  `dqcheckr_invalid_config` error instead of aborting mid-check.
* `run_custom_checks()` now validates each returned element (required fields
  and a valid status) and aborts with `dqcheckr_invalid_custom_checks` naming
  the offending element, instead of failing later with misleading errors.
* Snapshot writes are now wrapped in a single transaction, so a failure can
  no longer leave a `snapshots` row without its `column_snapshots` stats;
  column-level custom results are batch-inserted.
* The snapshot `run_timestamp` and the report filename are now derived from
  one timestamp taken at the start of the run. Previously they came from two
  separate clock reads, so links that reconstruct the report filename from
  the snapshot timestamp (as the GUI does) could intermittently point at a
  file with a name one second off.
* `compare_snapshots()` no longer announces (and offers to open) a drift
  report path when Quarto is unavailable and no report was written.
* Explicitly supplied snapshot IDs are now validated to belong to the
  requested dataset; previously IDs from another dataset silently produced a
  cross-dataset "drift" comparison.
* Rendered reports are moved from the render directory with a copy+delete
  fallback when `file.rename()` fails across filesystems (e.g. a
  network-share report directory); previously the move failed silently.
* QC-10 (numeric bounds) now counts violating rows rather than distinct
  values — a million rows of the same out-of-range value no longer reads as
  "1 out-of-range value(s)".
* QC-09 (allowed values) compares numerically when the YAML rule supplies
  numbers, so a file value of `"2.10"` matches an allowed value of `2.1`.
* `read_recent_snapshots()`'s empty-database fallback now has the same
  columns as the live query (it was missing `comparison_mode`,
  `render_status`, and `type_changed_cols_vs_previous`).

## New features

* New `report_file` column in the `snapshots` table stores the rendered
  report's filename outright (auto-migrated into existing databases), so
  consumers no longer need to reconstruct it from the run timestamp.
  `read_recent_snapshots()` returns it; `NA` for pre-0.2.3 rows.

## Documentation

* `run_dq_check()` and `compare_snapshots()` now document that relative
  `snapshot_db` / `report_output_dir` paths resolve against the working
  directory, not `config_dir`.
* `infer_col_type()` documents its date-format precedence, the
  all-must-parse rule, and the all-8-digit-identifier caveat, with a pointer
  to `column_types` overrides.

## Performance

* Column types are now inferred once per data frame and shared across all
  type-dependent checks. `run_qc_checks()` and the individual check functions
  gain an optional `types` argument; previously each of QC-06/07/08/11/15,
  the column statistics, and five comparison checks re-ran full-column type
  inference (five date parses plus a numeric parse) independently — the
  dominant cost on large files.
* `infer_col_type()` rejects non-matching date formats from a 100-value head
  sample before scanning the full column (results are identical; only the
  rejection path gets cheaper).
* `compute_col_stats()` builds one data frame per column instead of one per
  statistic row, cutting allocations on wide files.

# dqcheckr 0.2.2

## New features

* New optional CSV config key `csv_skip` (parallel to `fwf_skip`):
  `read_dataset()` now forwards `skip = config$csv_skip %||% 0L` to
  `readr::read_delim()`. This lets a config supply an explicit `col_names`
  list *and* drop the file's original header row — required for delivery
  files whose header repeats column names (e.g. a header that repeats
  `Name`/`Amount` per bundled record), where the real header is unusable and
  must be replaced positionally. Defaults to `0L`, so existing configs are
  byte-for-byte unaffected.

## Internal

* `?dqcheckr` package help now resolves (the `"_PACKAGE"` doc block no
  longer carries `@noRd`).
* Added a test for an out-of-range `csv_skip` value (skip exceeding the row
  count yields a zero-row frame).
* All negative tests now assert on a typed error class rather than using a
  bare `expect_error()`.

# dqcheckr 0.2.1

## Bug fixes

* Report and drift filename slugs now use UTC consistently, matching the
  UTC timestamps stored in the snapshot DB.
* Removed redundant `@importFrom` declarations for template-only packages.
* Removed dead `read_pass_rate_trend()` function from `drift.R`.
* `CP-07` type-change comparison now uses a single guard so it only runs the
  non-numeric rate comparison when both snapshots classify the column as
  numeric — eliminates spurious `WARN`s on type-changed columns.
* `read_dataset()` now forwards the `col_names` config key to
  `readr::read_delim()`, so headerless CSVs are read correctly.
* `read_dataset()` now forwards the `quote_char` config key to
  `readr::read_delim()` as `quote =`.

## Internal

* All `rlang::abort()` calls (27 sites) now carry a typed, two-level class
  hierarchy (`c("<specific>", "dqcheckr_error")`), letting callers catch
  errors broadly or precisely.
* Consolidated shared test fixtures into `helper.R`.

# dqcheckr 0.2.0

## New features

* New `compare_snapshots()` and `list_snapshots()` functions for drift analysis.
  Compares any two historical snapshots and optionally renders an HTML drift
  report with per-column statistical drift, schema changes, and trend charts.
* New `resolve_col_type()` function: returns the effective type for a column,
  respecting per-column type overrides set in the `column_types` config key.
* New `QC-15` outlier detection check (`check_outliers()`). Configured via
  `max_z_score` and/or `iqr_fence_multiplier`; skipped silently when neither is
  set.
* `check_key_uniqueness()` (QC-12) now supports composite keys: set
  `key_columns` to a character vector in the dataset YAML.
* `check_min_row_count()` (QC-14) gains `max_row_count` and `max_file_size_mb`
  thresholds.
* `col_threshold()` and `table_threshold()` added as internal helpers;
  `column_rules` per-column threshold overrides are now correctly stored in
  `column_snapshots.threshold` (G-01).

## Behaviour changes

* Reports migrated from rmarkdown to Quarto. `render_report()` uses
  `quarto::quarto_render()` and returns `NULL` with a warning when Quarto CLI
  is not installed.
* `compare_schema()` (CP-02) split into three separate result objects:
  CP-02a (new columns), CP-02b (dropped columns), CP-02c (type changes).
* `compare_non_numeric_rate()` (CP-07) now always emits a result for every
  eligible column, including PASS for columns where the rate did not increase
  (G-02).
* `run_timestamp` is now stored in ISO-8601 UTC format
  (`2026-01-01T12:00:00Z`) rather than local time (RC-07).
* `snapshots` table gains three columns on first use: `comparison_mode`,
  `render_status`, and `type_changed_cols_vs_previous`. Existing 0.1.x
  databases are auto-migrated on the first 0.2.0 run.
* SQLite foreign key enforcement is now explicitly enabled on every connection
  (`PRAGMA foreign_keys = ON`).
* `detect_files()` uses filename as a secondary sort when two files share the
  same modification time, making folder-mode ordering deterministic (RC-01).
* `check_allowed_values()` (QC-09), `compare_new_values()` (CP-05), and
  `compare_dropped_values()` (CP-06) cap `observed` at 20 values with an
  `"... and N more"` suffix (RC-04, RC-05).
* `check_non_numeric()` (QC-11) gains a `warn_non_numeric_rate` config key for
  a separate WARN threshold (C-01).
* `compare_missing_rate()` (CP-03) gains a `missing_rate_change_severity`
  config key (`warn` / `fail`) (B-07).
* `compare_column_order()` (CP-08) gains a `column_order_severity` config key
  that overrides the format-based default (C-02).
* `compute_col_stats()` stores the numeric mean under the key
  `numeric_parseable_mean` (renamed from `numeric_mean`) to clarify that
  non-parseable values are excluded from the calculation (C-04).
* Comparison summary in the HTML report now lists all FAIL/WARN messages as a
  bullet list rather than picking the single worst result (C-05).
* `compare_snapshots()` uses the full merged per-dataset config for drift
  threshold comparisons, so `***` markers match the original check run for
  datasets with `rule_overrides` (G-05/G-06).
* `compute_col_stats()` unused `qc_results` parameter removed (D-01).

# dqcheckr 0.1.1

* `flag_new_columns`, `flag_dropped_columns`, `flag_type_changes` (in CP-02) and
  `flag_column_order_change` (CP-08) are now honoured. Setting any flag to `false`
  suppresses the corresponding check from the report. Schema changes are still
  tracked in the SQLite snapshot regardless of flags.
* `type_inference_threshold` is now configurable per dataset via `rule_overrides`
  in the dataset YAML (or `default_rules` in the global config). Previously fixed
  at 90%, it now defaults to 90% if not set. Affects QC-06, QC-07, QC-08, QC-11,
  CP-02, CP-04, CP-05, CP-06, and CP-07.

# dqcheckr 0.1.0

Initial release.

* Single-snapshot quality checks: QC-01 to QC-14 (missing rate, empty columns,
  duplicate rows, row/column counts, inferred types, numeric stats, distinct
  counts, allowed values, numeric bounds, non-numeric rate, key uniqueness,
  regex pattern, minimum row count) and SC-01/SC-02 (schema contract).
* Version comparison checks: CP-01 to CP-08 (row count change, schema diff,
  missing rate change, numeric mean shift, new/dropped distinct values,
  non-numeric rate change, column order).
* Custom organisation-specific checks via a plain R file.
* Self-contained HTML report with check tables, historical trend charts, and
  column statistics appendix.
* SQLite snapshot database for long-term trend tracking.
* Supports CSV and fixed-width (FWF) file formats.
* Configuration via global `dqcheckr.yml` and per-dataset YAML files.
