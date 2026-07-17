# =============================================================================
# makedata.R — regenerate the fixed-width demo file from the CSV
# =============================================================================
#
# demo.R runs dqcheckr against the Star Wars data in two formats. The CSV
# (data/starwars.csv) is authored directly; the fixed-width file
# (data/starwars.fwf) is DERIVED from it by this script so the two always hold
# the same records.
#
# HOW TO RUN
#   Set the working directory to this demonstrations/ folder, then:
#     Rscript makedata.R
#   Outputs (both under data/):
#     starwars.fwf            — header row + one fixed-width row per record
#     starwars_fwf_spec.csv   — the column widths, for reference
#
# The widths written here MUST match fwf_widths in config/starwars_fwf.yml.
# They are computed as pmax(published width, longest value) so a field can
# never be truncated: if a future edit to starwars.csv lengthens a column,
# re-run this script and copy the new widths into the YAML.
# =============================================================================

csv <- read.csv("data/starwars.csv", stringsAsFactors = FALSE,
                colClasses = "character", na.strings = "")

# The published layout (config/starwars_fwf.yml). height and birth_year carry
# deliberate slack beyond their data; the rest hug the data. Kept as the floor.
published <- c(name = 21, height = 6, mass = 4, hair_color = 13, skin_color = 19,
               eye_color = 13, birth_year = 10, sex = 14, gender = 9,
               homeworld = 14, species = 14, films = 131, vehicles = 35,
               starships = 100)
stopifnot(identical(names(csv), names(published)))

data_max <- vapply(csv, function(col) max(nchar(col), 0L, na.rm = TRUE),
                   integer(1))
widths <- pmax(published, data_max[names(published)])

# Left-justify each value into its field, empty string for NA. formatC never
# truncates, and widths >= data_max guarantees every value fits exactly.
pad <- function(x, w) formatC(ifelse(is.na(x), "", x), width = w, flag = "-")

body   <- do.call(paste0, Map(pad, csv, widths))
header <- paste0(Map(pad, as.list(names(csv)), widths), collapse = "")

writeLines(c(header, body), "data/starwars.fwf")
write.csv(data.frame(column = names(widths), width = unname(widths)),
          "data/starwars_fwf_spec.csv", row.names = FALSE)

cat("Wrote data/starwars.fwf:", length(body), "records,",
    "line width", sum(widths), "\n")
if (any(widths != published))
  cat("NOTE: widths changed from the published spec for:",
      paste(names(widths)[widths != published], collapse = ", "),
      "-> update config/starwars_fwf.yml fwf_widths to match.\n")
