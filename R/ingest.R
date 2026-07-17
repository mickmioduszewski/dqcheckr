#' Detect current and previous dataset files
#'
#' Resolves the current and previous file paths from the configuration. If
#' \code{current_file} is set explicitly, it is used directly. Otherwise the
#' two most recently modified files in \code{folder} are used.
#'
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}.
#'
#' @return A named list with elements \code{current} (character path) and
#'   \code{previous} (character path or \code{NULL}).
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg <- load_config("starwars_csv", config_dir = cfg_dir)
#' cfg$current_file <- system.file("demonstrations/data/starwars.csv",
#'                                  package = "dqcheckr")
#' files <- detect_files(cfg)
#' files$current
#'
#' @export
detect_files <- function(config) {
  if (!is.null(config$current_file)) {
    if (!file.exists(config$current_file)) {
      rlang::abort(paste0("current_file not found: ", config$current_file),
                   class = c("dqcheckr_missing_file", "dqcheckr_error"))
    }
    previous <- NULL
    if (!is.null(config$previous_file)) {
      if (!file.exists(config$previous_file)) {
        rlang::abort(paste0("previous_file not found: ", config$previous_file),
                     class = c("dqcheckr_missing_file", "dqcheckr_error"))
      }
      previous <- config$previous_file
    }
    return(list(current = config$current_file, previous = previous))
  }

  folder <- config$folder
  if (is.null(folder) || !dir.exists(folder)) {
    rlang::abort(paste0("Folder not found: ", folder %||% "(NULL)"),
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))
  }

  files <- list.files(folder, full.names = TRUE)
  # list.files() includes subdirectories in a non-recursive listing; a newly
  # created folder must never be picked as the "current file" by mtime.
  files <- files[!dir.exists(files)]
  if (length(files) == 0) {
    rlang::abort(paste0("No files found in folder: ", folder),
                 class = c("dqcheckr_missing_file", "dqcheckr_error"))
  }

  files <- files[order(file.mtime(files), basename(files), decreasing = TRUE)]
  list(
    current  = files[1],
    previous = if (length(files) >= 2) files[2] else NULL
  )
}

# Formal aliases for plain ASCII. ASCII is a strict subset of UTF-8, so a file
# declared as any of these always reads identically under UTF-8 -- but passed
# to readr's locale verbatim, a delivery containing a byte above 127 aborts
# iconv inside vroom and can take the whole R process down. Reading as UTF-8
# instead is lossless and removes that failure mode entirely.
.ascii_aliases <- c("ASCII", "US-ASCII", "ANSI_X3.4-1968", "ANSI_X3.4-1986",
                    "ISO646-US", "646")

normalise_encoding <- function(enc) {
  if (toupper(trimws(enc)) %in% .ascii_aliases) "UTF-8" else enc
}

# Classify an *effective* (post-normalise) encoding into how it can be verified:
#   "utf8"        -- validity is scannable (scan_file_encoding()).
#   "single_byte" -- ISO-8859-x / Windows-125x / Latin-n: every byte sequence is
#                    valid by construction, so a scan is meaningless and PASS is
#                    legitimate.
#   "other"       -- multi-byte or unknown (UTF-16/32, Shift-JIS, GB18030, ...):
#                    NOT validity-checked. QC-16 must WARN rather than claim the
#                    file is "single-byte, valid by construction".
.encoding_class <- function(enc) {
  u <- toupper(trimws(enc))
  if (u %in% c("UTF-8", "UTF8")) return("utf8")
  if (grepl("^(ISO[- ]?8859|LATIN[- ]?[0-9]|WINDOWS[- ]?125[0-9]|CP125[0-9])", u))
    return("single_byte")
  "other"
}

# Number of trailing bytes of `buf` that begin a UTF-8 multi-byte sequence which
# may continue in the next chunk, and so must be held back rather than validated
# at a chunk boundary. Returns 0 unless the buffer ends with a genuinely
# incomplete sequence (a valid lead byte followed by fewer continuation bytes
# than its length requires); ASCII, complete sequences, and malformed bytes all
# return 0 -- malformed-ness is local, so the validator will catch it in-chunk.
.utf8_incomplete_tail <- function(buf) {
  n <- length(buf)
  if (n == 0L) return(0L)
  i    <- n
  cont <- 0L
  while (i >= 1L && cont < 3L && bitwAnd(as.integer(buf[i]), 0xC0L) == 0x80L) {
    cont <- cont + 1L                    # walk back over continuation bytes
    i    <- i - 1L
  }
  if (i < 1L) return(0L)                 # only continuation bytes: malformed
  lead <- as.integer(buf[i])
  need <- if (bitwAnd(lead, 0x80L) == 0x00L) 1L
          else if (bitwAnd(lead, 0xE0L) == 0xC0L) 2L
          else if (bitwAnd(lead, 0xF0L) == 0xE0L) 3L
          else if (bitwAnd(lead, 0xF8L) == 0xF0L) 4L
          else 1L                        # stray continuation / invalid lead
  have <- cont + 1L                      # continuations seen plus the lead byte
  if (need > 1L && have < need) have else 0L
}

# UTF-8 validity scan, run before vroom ever sees the file. Streamed in bounded
# chunks so a multi-GB delivery is verified in flat memory instead of being read
# into one raw vector (which exhausts memory on the network-share hosts dqcheckr
# deploys to). Only the "is this valid UTF-8?" question has a deterministic
# answer; when the file is not valid UTF-8, the specific legacy encoding can only
# be guessed statistically, so the guess is reported but never trusted blindly.
scan_file_encoding <- function(path, chunk_size = 64L * 1024L * 1024L) {
  size <- suppressWarnings(file.size(path))
  if (is.na(size) || size <= 0) return(list(valid = TRUE, guess = NULL))

  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  carry <- raw(0)   # trailing bytes of a possibly-incomplete sequence
  repeat {
    chunk <- readBin(con, what = "raw", n = chunk_size)
    if (length(chunk) == 0L) break
    buf <- if (length(carry) > 0L) c(carry, chunk) else chunk

    tail_n <- .utf8_incomplete_tail(buf)
    head_n <- length(buf) - tail_n
    head_bytes <- if (head_n > 0L) buf[seq_len(head_n)] else raw(0)
    carry      <- if (tail_n > 0L) buf[seq.int(head_n + 1L, length(buf))] else raw(0)

    if (length(head_bytes) > 0L && !stringi::stri_enc_isutf8(head_bytes))
      return(list(valid = FALSE, guess = .guess_legacy_encoding(head_bytes)))
  }
  # Bytes still held at EOF are a multi-byte sequence truncated by the file end.
  if (length(carry) > 0L && !stringi::stri_enc_isutf8(carry))
    return(list(valid = FALSE, guess = .guess_legacy_encoding(carry)))
  list(valid = TRUE, guess = NULL)
}

# Locate the first chunk containing non-ASCII bytes and run ICU's charset
# detector on it. The detector must see the offending bytes: a head sample of
# a file whose first accented character sits millions of rows in guesses
# "ASCII" -- the exact trap this scan exists to avoid. Chunking is safe here
# because "contains a byte above 127" is a per-byte property, unlike UTF-8
# sequence validity.
.guess_legacy_encoding <- function(raw) {
  chunk_size <- 1e6
  n     <- length(raw)
  start <- 1
  window <- NULL
  while (start <= n) {
    end   <- min(start + chunk_size - 1, n)
    piece <- raw[start:end]
    if (!stringi::stri_enc_isascii(piece)) {
      window <- piece
      break
    }
    start <- end + 1
  }
  if (is.null(window)) return(NULL)
  det <- tryCatch(stringi::stri_enc_detect(window)[[1]], error = function(e) NULL)
  if (is.null(det) || nrow(det) == 0) return(NULL)
  # The file as a whole is not valid UTF-8, so drop Unicode candidates the
  # detector may still offer for a locally-valid window.
  cand <- det$Encoding[!grepl("^UTF", det$Encoding, ignore.case = TRUE)]
  if (length(cand) == 0) NULL else cand[1]
}

# Encoding used to complete the run when the declared UTF-8 turned out to be
# wrong. The guess is honoured only if it names a single-byte encoding, where
# every byte sequence is valid by construction and iconv cannot abort;
# anything else falls back to ISO-8859-1 for the same reason.
.safe_fallback_encoding <- function(guess) {
  if (!is.null(guess) &&
      grepl("^(ISO-8859|windows-125)", guess, ignore.case = TRUE)) guess
  else "ISO-8859-1"
}

#' Read a dataset file into a data frame
#'
#' Reads a CSV or fixed-width file, coercing all columns to character and
#' trimming whitespace. Encoding and delimiter are taken from \code{config}.
#' A declared encoding of ASCII (or a formal alias such as \code{US-ASCII})
#' is read as UTF-8: ASCII is a strict subset of UTF-8, so this is lossless,
#' and it protects against deliveries whose non-ASCII bytes appear beyond any
#' sample a sniffer looked at. When the effective encoding is UTF-8 the whole
#' file is validity-scanned before parsing; a delivery that is not valid
#' UTF-8 is read using a single-byte fallback encoding instead, and the
#' mismatch is surfaced by \code{\link{check_file_encoding}} (QC-16) as a
#' FAIL result rather than crashing the run.
#'
#' @param path Character. Path to the file to read.
#' @param config Named list. Merged configuration as returned by
#'   \code{\link{load_config}}. Must include \code{format} (\code{"csv"} or
#'   \code{"fwf"}). For CSV files, \code{col_names} (an explicit column-name
#'   list) and \code{csv_skip} (number of leading lines to drop, e.g. a real
#'   header row that is being replaced by \code{col_names}) are optional and
#'   default to using the file's own header and \code{0L} respectively. For
#'   FWF files, \code{fwf_widths} is required and \code{fwf_col_names} and
#'   \code{fwf_skip} are optional.
#'
#' @return A data frame with all columns as character vectors.
#'
#' @examples
#' cfg_dir <- system.file("demonstrations/config", package = "dqcheckr")
#' cfg  <- load_config("starwars_csv", config_dir = cfg_dir)
#' path <- system.file("demonstrations/data/starwars.csv", package = "dqcheckr")
#' df   <- read_dataset(path, cfg)
#'
#' @export
read_dataset <- function(path, config) {
  fmt <- tolower(config$format %||% "csv")
  enc <- normalise_encoding(config$encoding %||% "UTF-8")

  enc_class <- .encoding_class(enc)
  enc_info <- list(declared = config$encoding %||% "UTF-8", used = enc,
                   scanned = FALSE, valid = TRUE, guess = NULL, scan_error = NULL,
                   enc_class = enc_class)
  if (enc_class == "utf8") {
    # A scan failure must never block the read; readr raises its own typed error
    # below if the file is genuinely unreadable. But it must not be swallowed
    # into a confident PASS either (e.g. an out-of-memory readBin on a huge
    # delivery): record the failure so validity reads as *unknown* (NA), and
    # QC-16 turns that into a WARN rather than a green "valid by construction".
    scan <- tryCatch(scan_file_encoding(path), error = function(e) e)
    if (inherits(scan, "condition")) {
      enc_info$valid      <- NA
      enc_info$scan_error <- conditionMessage(scan)
    } else {
      enc_info$scanned <- TRUE
      if (!scan$valid) {
        enc           <- .safe_fallback_encoding(scan$guess)
        enc_info$valid <- FALSE
        enc_info$guess <- scan$guess
        enc_info$used  <- enc
      }
    }
  }

  if (fmt == "csv") {
    delim <- config$delimiter %||% ","
    df <- tryCatch(
      readr::read_delim(
        path,
        delim      = delim,
        col_names  = config$col_names  %||% TRUE,
        skip       = config$csv_skip   %||% 0L,
        quote      = config$quote_char %||% '"',
        col_types  = readr::cols(.default = "c"),
        locale     = readr::locale(encoding = enc),
        show_col_types = FALSE
      ),
      error = function(e) rlang::abort(paste0("Failed to parse file '", path, "': ", conditionMessage(e)),
                                       class = c("dqcheckr_parse_error", "dqcheckr_error"))
    )
  } else if (fmt == "fwf") {
    if (is.null(config$fwf_widths)) {
      rlang::abort("fwf_widths must be set in config for fixed-width files",
                   class = c("dqcheckr_invalid_config", "dqcheckr_error"))
    }
    df <- tryCatch(
      readr::read_fwf(
        path,
        col_positions = readr::fwf_widths(
          config$fwf_widths,
          col_names = config$fwf_col_names
        ),
        col_types  = readr::cols(.default = "c"),
        locale     = readr::locale(encoding = enc),
        skip       = config$fwf_skip %||% 0L,
        show_col_types = FALSE
      ),
      error = function(e) rlang::abort(paste0("Failed to parse file '", path, "': ", conditionMessage(e)),
                                       class = c("dqcheckr_parse_error", "dqcheckr_error"))
    )
  } else {
    rlang::abort(paste0("Unsupported format: '", config$format, "'. Must be 'csv' or 'fwf'."),
                 class = c("dqcheckr_invalid_config", "dqcheckr_error"))
  }

  df <- as.data.frame(df, stringsAsFactors = FALSE)
  for (col in names(df)) {
    df[[col]] <- trimws(df[[col]])
  }
  # Consumed by check_file_encoding() (QC-16) in run_qc_checks().
  attr(df, "dq_encoding") <- enc_info
  df
}
