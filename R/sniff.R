# sniff_dataset(): pure inference over a delivery file -- the detection half
# of the config generator (plan step 6). No side effects: it reads the file
# (full-file streamed encoding scan, then a bounded head sample) and returns a
# plain list the writer (generate_dataset_config, step 7) turns into YAML.
# Detection REUSES the package's existing single sources of truth --
# scan_file_encoding()/normalise_encoding() for encoding and infer_col_type()
# for types -- never a parallel implementation (the GUI's divergence bug class
# must not be reborn here).

# Lines of the head sample used for structure detection and type inference.
.sniff_sample_lines <- 1000L

# Detect the delimiter/quote pair: the candidate whose field counts are
# identical across all sampled lines with >= 2 fields wins; ties go to the
# higher field count. Returns NULL when no candidate splits consistently
# (single-column CSV or a fixed-width file).
.sniff_delimiter <- function(lines, quotes = c('"', "'")) {
  candidates <- c(",", ";", "\t", "|")
  best <- NULL
  for (q in quotes) {
    for (d in candidates) {
      counts <- vapply(lines, function(l)
        length(tryCatch(.split_fields(l, d, q), error = function(e) character())),
        integer(1), USE.NAMES = FALSE)
      if (length(unique(counts)) == 1 && counts[1] >= 2 &&
          (is.null(best) || counts[1] > best$n_fields))
        best <- list(delimiter = d, quote_char = q, n_fields = counts[1])
    }
    if (!is.null(best)) break   # default quote worked; don't prefer the exotic one
  }
  best
}

# Header heuristic: the first row is a header when none of its fields parses
# as a number but at least one body field does. An all-text file is assumed
# headed (the common case); an all-numeric first row is data.
.sniff_header <- function(first_fields, body_fields) {
  is_num <- function(x) !is.na(suppressWarnings(as.numeric(x)))
  if (any(is_num(first_fields))) return(FALSE)
  if (length(body_fields) == 0) return(TRUE)          # nothing to compare: assume headed
  TRUE
}

# Rename duplicate header names positionally: the 2nd, 3rd, ... occurrence of
# a name gets a _2/_3 suffix. Returns list(names=..., renamed_from=...) where
# renamed_from maps new name -> original (NULL when nothing was renamed).
.dedupe_names <- function(nms) {
  if (!anyDuplicated(nms)) return(list(names = nms, renamed_from = NULL))
  seen  <- new.env(parent = emptyenv())
  out   <- character(length(nms))
  from  <- character(0)
  for (i in seq_along(nms)) {
    n   <- nms[i]
    cnt <- (get0(n, envir = seen, ifnotfound = 0L)) + 1L
    assign(n, cnt, envir = seen)
    if (cnt == 1L) out[i] <- n
    else {
      out[i] <- paste0(n, "_", cnt)
      from[out[i]] <- n
    }
  }
  list(names = out, renamed_from = from)
}

# Per-column types over sampled cell matrix (columns as list of character
# vectors), via the package's one type-inference implementation.
.sniff_types <- function(cols) {
  vapply(cols, function(v) infer_col_type(trimws(v)), character(1))
}

# Key-column candidates: sampled columns whose values are all present and
# unique -- plausible row identities, offered for the human to confirm.
.sniff_key_candidates <- function(cols) {
  ok <- vapply(cols, function(v) {
    v <- trimws(v)
    length(v) > 0 && !any(.missing_vals(v)) && !anyDuplicated(v)
  }, logical(1))
  names(cols)[ok]
}

#' Sniff a delivery file's structure
#'
#' Pure inference, no side effects: inspects a delivery file and returns what
#' a config would need -- format, encoding, delimiter/quote, header presence,
#' column names (with duplicate header names renamed positionally), per-column
#' types, and key-column candidates -- as a plain list. This is the detection
#' half of the config generator; the writer turns it into a commented YAML.
#'
#' Encoding uses the same full-file streamed scan as \code{read_dataset()}
#' (\code{scan_file_encoding()}): a file that is not valid UTF-8 gets the same
#' single-byte fallback the reader would use, recorded in
#' \code{encoding_guess}. Types come from \code{\link{infer_col_type}} -- the
#' one implementation, so the sniff can never disagree with run-time
#' classification. Structure detection reads a bounded head sample
#' (\code{n_sample_rows} reports how many data rows informed it), never the
#' file body.
#'
#' Fixed-width files: when the sampled lines are all the same width and no
#' delimiter splits them, boundaries are guessed with
#' \code{readr::fwf_empty()} (blank-gutter detection). A packed file (no
#' blank gutters) sets \code{fwf_packed = TRUE} and \code{fwf_widths = NULL}
#' rather than guessing wrongly -- the generator emits a \code{TODO} the
#' validator refuses to run.
#'
#' Every headline field's origin is recorded in \code{provenance}
#' (\code{"detected"}, \code{"default"}, or \code{"generated"}), so the
#' writer can emit detected values live and defaults commented out.
#'
#' @param path Character. Path to the delivery file.
#'
#' @return A named list: \code{path}, \code{format} (\code{"csv"}/\code{"fwf"}),
#'   \code{encoding}, \code{encoding_valid_utf8}, \code{encoding_guess},
#'   \code{bom}, \code{delimiter}, \code{quote_char}, \code{header},
#'   \code{csv_skip}, \code{col_names}, \code{renamed_from} (new name ->
#'   original, \code{NULL} unless duplicates were renamed), \code{fwf_widths},
#'   \code{fwf_col_names}, \code{fwf_packed}, \code{column_types},
#'   \code{key_column_candidates}, \code{expected_columns},
#'   \code{n_sample_rows}, \code{provenance}.
#'
#' @examples
#' f <- tempfile(fileext = ".csv")
#' writeLines(c("id,amount", "A1,10", "A2,20"), f)
#' s <- sniff_dataset(f)
#' s$format; s$col_names; s$column_types
#'
#' @export
sniff_dataset <- function(path) {
  if (!file.exists(path))
    rlang::abort(paste0("File not found: ", path),
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))

  # Encoding first (full-file streamed scan, same as read_dataset). The head
  # sample is then read under the effective encoding.
  scan <- scan_file_encoding(path)
  encoding <- if (scan$valid %in% TRUE || is.na(scan$valid)) "UTF-8"
              else .safe_fallback_encoding(scan$guess)

  lines <- .read_head_lines(path, .sniff_sample_lines, encoding)
  if (length(lines) == 0 || !any(nzchar(trimws(lines))))
    rlang::abort(paste0("File is empty: ", path),
                 class = c("dqcheckr_empty_file", "dqcheckr_error"))
  bom <- startsWith(readChar(path, 3L, useBytes = TRUE), "\xef\xbb\xbf")
  lines <- lines[nzchar(lines)]

  provenance <- c(format = "detected", encoding = "detected",
                  delimiter = "default", quote_char = "default",
                  header = "detected", col_names = "detected")

  res <- list(path = path, format = "csv", encoding = encoding,
              encoding_valid_utf8 = scan$valid, encoding_guess = scan$guess,
              bom = bom, delimiter = NULL, quote_char = NULL, header = NULL,
              csv_skip = 0L, col_names = NULL, renamed_from = NULL,
              fwf_widths = NULL, fwf_col_names = NULL, fwf_packed = FALSE,
              column_types = character(0), key_column_candidates = character(0),
              expected_columns = character(0), n_sample_rows = 0L,
              provenance = provenance)

  delim <- .sniff_delimiter(lines)

  if (is.null(delim) && length(lines) >= 2 &&
      length(unique(nchar(lines))) == 1) {
    # -- fixed width: equal-length records that no delimiter splits ------------
    res$format <- "fwf"
    record_len <- nchar(lines[1])
    pos <- tryCatch(readr::fwf_empty(path, n = min(length(lines), 100L)),
                    error = function(e) NULL)
    if (is.null(pos) || length(pos$begin) <= 1) {
      # Packed: no blank gutters to detect. An explicit marker, never a wrong
      # confident guess -- the generator emits TODO widths from this.
      res$fwf_packed <- TRUE
      res$provenance[["col_names"]] <- "generated"
    } else {
      widths <- diff(c(pos$begin, record_len))   # contiguous cover incl. gutters
      res$fwf_widths    <- as.integer(widths)
      res$fwf_col_names <- paste0("col_", seq_along(widths))
      res$provenance[["col_names"]] <- "generated"
      starts <- cumsum(c(1L, widths[-length(widths)]))
      cols <- lapply(seq_along(widths), function(i)
        substr(lines, starts[i], starts[i] + widths[i] - 1L))
      names(cols) <- res$fwf_col_names
      res$column_types          <- .sniff_types(cols)
      res$key_column_candidates <- .sniff_key_candidates(cols)
      res$expected_columns      <- res$fwf_col_names
      res$n_sample_rows         <- length(lines)
    }
    return(res)
  }

  # -- CSV (delimited, possibly single-column) ---------------------------------
  if (is.null(delim)) {
    # Single column: every line is one field. Delimiter/quote are defaults.
    fields_by_line <- as.list(lines)
    res$delimiter  <- .default_read$delimiter
    res$quote_char <- .default_read$quote_char
  } else {
    res$delimiter  <- delim$delimiter
    res$quote_char <- delim$quote_char
    res$provenance[["delimiter"]] <- "detected"
    if (!identical(delim$quote_char, .default_read$quote_char))
      res$provenance[["quote_char"]] <- "detected"
    fields_by_line <- lapply(lines, .split_fields,
                             delim = delim$delimiter, quote = delim$quote_char)
  }

  first <- unlist(fields_by_line[[1]])
  body  <- if (length(fields_by_line) > 1)
    unlist(fields_by_line[-1], use.names = FALSE) else character(0)
  res$header <- .sniff_header(first, body)
  if (length(fields_by_line) == 1) res$provenance[["header"]] <- "default"

  n_cols <- length(first)
  if (res$header) {
    dd <- .dedupe_names(first)
    res$col_names <- dd$names
    # list-element <- NULL would DELETE the field; keep it present-but-NULL.
    if (!is.null(dd$renamed_from)) {
      res$renamed_from <- dd$renamed_from
      res$csv_skip     <- 1L
    }
    data_rows <- fields_by_line[-1]
  } else {
    res$col_names <- paste0("col_", seq_len(n_cols))
    res$provenance[["col_names"]] <- "generated"
    data_rows <- fields_by_line
  }

  data_rows <- Filter(function(f) length(f) == n_cols, data_rows)
  res$n_sample_rows <- length(data_rows)
  cols <- lapply(seq_len(n_cols), function(i)
    vapply(data_rows, `[[`, character(1), i))
  names(cols) <- res$col_names
  if (res$n_sample_rows > 0) {
    res$column_types          <- .sniff_types(cols)
    res$key_column_candidates <- .sniff_key_candidates(cols)
  }
  res$expected_columns <- res$col_names
  res
}
