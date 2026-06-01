# Changelog

## dqcheckr 0.2.0

### Breaking changes

- **DuckDB connection required for all check functions.** The
  `con = NULL` pure-R execution path has been removed. All check,
  comparison, and ingest functions now require a DuckDB connection.
  There is no automatic fallback.

- **[`read_dataset()`](https://mickmioduszewski.github.io/dqcheckr/reference/read_dataset.md)
  requires `con`.** The function now aborts with an informative message
  if called without a connection.

- **DuckDB replaces SQLite** for snapshot storage. Existing `.sqlite`
  databases must be migrated with
  `inst/scripts/migrate_sqlite_to_duckdb.R`. Update `snapshot_db` in
  `dqcheckr.yml` to point to the new `.duckdb` path.

- **Quarto replaces rmarkdown** for HTML reports. Install Quarto CLI
  from <https://quarto.org>.

- **CP-02 split into three result objects**: `CP-02a` (new columns),
  `CP-02b` (dropped columns), `CP-02c` (type changes). Code filtering on
  `check_id == "CP-02"` must be updated.

- **`run_timestamp`** is now stored in UTC ISO-8601 format
  (`YYYY-MM-DDTHH:MM:SSZ`).

- **`numeric_mean`** stat key renamed to **`numeric_parseable_mean`** in
  `column_snapshots`.

- **`readr` moved from `Imports` to `Suggests`.** Packages that relied
  on readr as a transitive dependency of dqcheckr must now declare it
  directly.

### New features

- **Native CSV ingestion via DuckDB.** CSV files are read directly into
  DuckDB using `read_csv` with `strict_mode = false`, eliminating the
  previous readr-based workaround for files with many columns and quoted
  comma-containing fields (a sniffer bug in DuckDB ≤ 1.5.x). Peak memory
  drops from ~2× to ~1× file size for large CSV inputs.

- **Native FWF ingestion via DuckDB.** Fixed-width files are read using
  a `chr(1)` (SOH) delimiter to treat each line as a single VARCHAR
  column, then `SUBSTR` extracts columns at their exact character
  positions. All three file formats — CSV, FWF, and Parquet — are now
  read natively by DuckDB with no intermediate R data.frame allocation.

- **Parquet input**: add `format: parquet` to the dataset YAML.

- **Outlier detection**
  ([`check_outliers()`](https://rdrr.io/pkg/dqcheckr/man/check_outliers.html),
  QC-16): configurable Z-score threshold per column via
  `column_rules.<col>.max_z_score`. Off by default.

- **File size check** (`check_file_size()`, QC-15): FAIL when file
  exceeds `max_file_size_mb`; always emits an INFO with the actual size.

- **Maximum row count** (`max_row_count`, QC-14b).

- **Multi-column composite key uniqueness**: `key_columns` now accepts a
  list.

- **[`compare_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/compare_snapshots.md)**
  compares any two historical snapshots by ID.

- **[`list_snapshots()`](https://mickmioduszewski.github.io/dqcheckr/reference/list_snapshots.md)**
  lists available snapshots.

- **Per-column type overrides** (`column_types` in dataset YAML).

- **Per-column threshold overrides** in `column_rules` for QC-01, QC-11,
  CP-03, CP-04, and CP-07.

### Behaviour changes

- All QC and CP checks execute as DuckDB SQL. The test suite exercises
  the same code path as production.

- [`detect_files()`](https://mickmioduszewski.github.io/dqcheckr/reference/detect_files.md)
  uses filename alphabetical order as a tiebreaker when modification
  times are equal.

- The `observed` field in QC-09, CP-05, and CP-06 is capped at 20
  values.

- CP-03 severity is configurable via `missing_rate_change_severity`.

- CP-08 severity is configurable via `column_order_severity`.

- `flag_*` keys suppress WARN from report but still write changes to
  snapshot db.

- QC-11 supports two-level WARN/FAIL via `warn_non_numeric_rate`.

## dqcheckr 0.1.1

- `flag_new_columns`, `flag_dropped_columns`, `flag_type_changes`, and
  `flag_column_order_change` are now honoured.
- `type_inference_threshold` is configurable per dataset.

## dqcheckr 0.1.0

Initial release.

- Single-snapshot quality checks: QC-01 to QC-14 and SC-01/SC-02.
- Version comparison checks: CP-01 to CP-08.
- Custom organisation-specific checks via a plain R file.
- Self-contained HTML report with check tables, trend charts, and column
  statistics appendix.
- SQLite snapshot database for long-term trend tracking.
- Supports CSV and fixed-width (FWF) file formats.
- Configuration via global `dqcheckr.yml` and per-dataset YAML files.
