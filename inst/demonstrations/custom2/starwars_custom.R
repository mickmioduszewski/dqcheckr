custom_checks <- function(df) {
  results <- list()

  is_human <- "species" %in% names(df) &
    !is.na(df$species) & tolower(df$species) == "human"

  # CC-01: Human height error — above 210
  if ("height" %in% names(df) && any(is_human)) {
    heights   <- suppressWarnings(as.numeric(df$height[is_human]))
    char_names <- if ("name" %in% names(df)) df$name[is_human] else rep(NA, sum(is_human))

    fail_names <- char_names[!is.na(heights) & heights > 210]
    n_fail     <- length(fail_names)

    results <- c(results, list(dq_result(
      check_id   = "CC-01",
      check_name = "Human height — above maximum",
      column     = "height",
      status     = if (n_fail > 0) "FAIL" else "PASS",
      observed   = if (n_fail > 0)
        sprintf("%d Human(s) with height > 210: %s",
                n_fail, paste(fail_names, collapse = ", "))
      else
        "No Human characters exceed height 210.",
      threshold  = "210",
      message    = if (n_fail > 0)
        sprintf("%d Human character(s) have height above 210.", n_fail)
      else
        "All Human characters are within the height maximum of 210."
    )))
  }

  # CC-02: Human height warning — elevated range 200-210
  if ("height" %in% names(df) && any(is_human)) {
    heights    <- suppressWarnings(as.numeric(df$height[is_human]))
    char_names <- if ("name" %in% names(df)) df$name[is_human] else rep(NA, sum(is_human))

    warn_names <- char_names[!is.na(heights) & heights > 199 & heights <= 210]
    n_warn     <- length(warn_names)

    results <- c(results, list(dq_result(
      check_id   = "CC-02",
      check_name = "Human height — elevated range",
      column     = "height",
      status     = if (n_warn > 0) "WARN" else "PASS",
      observed   = if (n_warn > 0)
        sprintf("%d Human(s) with height 200-210: %s",
                n_warn, paste(warn_names, collapse = ", "))
      else
        "No Human characters in the elevated height range (200-210).",
      threshold  = "200-210",
      message    = if (n_warn > 0)
        sprintf("%d Human character(s) have height between 200 and 210.", n_warn)
      else
        "No Human characters in the elevated height range."
    )))
  }

  # CC-03: Human mass warning — above 140
  if ("mass" %in% names(df) && any(is_human)) {
    masses     <- suppressWarnings(as.numeric(df$mass[is_human]))
    char_names <- if ("name" %in% names(df)) df$name[is_human] else rep(NA, sum(is_human))

    warn_names <- char_names[!is.na(masses) & masses > 140]
    n_warn     <- length(warn_names)

    results <- c(results, list(dq_result(
      check_id   = "CC-03",
      check_name = "Human mass — elevated",
      column     = "mass",
      status     = if (n_warn > 0) "WARN" else "PASS",
      observed   = if (n_warn > 0)
        sprintf("%d Human(s) with mass > 140: %s",
                n_warn, paste(warn_names, collapse = ", "))
      else
        "No Human characters exceed mass 140.",
      threshold  = "140",
      message    = if (n_warn > 0)
        sprintf("%d Human character(s) have mass above 140.", n_warn)
      else
        "All Human characters are within the mass threshold of 140."
    )))
  }

  results
}
