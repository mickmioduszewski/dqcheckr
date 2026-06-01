# dqcheckr demonstrations

Two runnable demonstrations using the Star Wars dataset from `dplyr`.

## Setup

Install dqcheckr, then copy this folder to a local working directory:

```r
# Install from GitHub
devtools::install_github("mickmioduszewski/dqcheckr")

# Copy demonstrations to ~/dqcheckr_demo
dest <- file.path(path.expand("~"), "dqcheckr_demo")
file.copy(system.file("demonstrations", package = "dqcheckr"),
          dirname(dest), recursive = TRUE)
file.rename(file.path(dirname(dest), "demonstrations"), dest)
```

Open the copied folder in RStudio and set the working directory to it:
**Session → Set Working Directory → To Source File Location**

---

## demo.R — Named-file mode

Checks the Star Wars dataset in both CSV and fixed-width format. Uses explicit
`current_file:` paths in the config — no folder scan.

```
data/
  starwars.csv        current file (CSV)
  starwars.fwf        current file (fixed-width)
config/
  dqcheckr.yml        global rules
  starwars_csv.yml    CSV dataset config
  starwars_fwf.yml    FWF dataset config
output/
  reports/            HTML reports written here
  snapshots.sqlite    run history written here
```

Run: open `demo.R` and source it. Two HTML reports open in the browser.

Expected result: **FAIL** on both — `vehicles` and `starships` columns
are genuinely sparse (87% and 77% missing) so they exceed the missing-rate
threshold. All other checks pass.

---

## demo2.R — Folder-scan mode with version comparison and custom checks

Compares two deliveries of the Star Wars dataset using automatic folder-scan
file detection. Applies custom human-specific checks.

```
data2/
  starwars_v1.csv     original data  (previous delivery)
  starwars_v2.csv     perturbed data (current delivery)
config2/
  dqcheckr.yml        global rules
  starwars_folder.yml folder-scan dataset config
custom2/
  starwars_custom.R   custom checks for human characters
output2/
  reports/            HTML reports written here
  snapshots.sqlite    run history written here
```

**Perturbations in v2** (all within configured thresholds — QC checks pass):

| Column | Change | Effect |
|--------|--------|--------|
| `height` | +15 to all values | ~8.6% mean shift — triggers CP-04 |
| `mass` | ×1.10 | ~10% mean shift — triggers CP-04 |
| `birth_year` | −5 to all values | ~5.7% mean shift — triggers CP-04 |
| `homeworld` | 5 characters → "Exegol" | new distinct value — triggers CP-05 |
| `species` | 1 character → "Chiss" | new distinct value — triggers CP-05 |

**Custom checks** (`custom2/starwars_custom.R`):

| Check | Condition | Status |
|-------|-----------|--------|
| CC-01 | Human with height > 210 | FAIL |
| CC-02 | Human with height 200–210 | WARN |
| CC-03 | Human with mass > 140 | WARN |

Run: open `demo2.R` and source it. One HTML report opens in the browser
showing QC checks, custom checks, and version comparison.

Expected result: **FAIL** — `vehicles`/`starships` missing rate (standard)
and CC-01 Human height (custom). Version comparison shows distribution
shifts across height, mass, and birth_year, plus new distinct values in
homeworld and species.
