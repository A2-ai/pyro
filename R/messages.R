#' Emit a message wrapped to the console width
#'
#' Used for prose such as the confirmation prompt's explanation. Lines
#' that carry a file path are printed with plain `message()` so the path
#' is never broken across lines.
#'
#' @param ... Pieces pasted together with no separator.
#' @param indent Number of spaces to indent every line. Used for the
#'   explanatory text under a header line.
#'
#' @keywords internal
#' @noRd
pyro_message <- function(..., indent = 0L) {
  text <- paste0(...)
  width <- getOption("width", 80L)
  width <- max(40L, min(width, 80L))
  lines <- strwrap(text, width = width, indent = indent, exdent = indent)
  message(paste(lines, collapse = "\n"))
}
