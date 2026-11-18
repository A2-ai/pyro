#' Convert a user-supplied directory to a canonical absolute path
#'
#' Paths are handed to the setup scripts and to uv without a shell, so
#' nothing downstream expands `~` or resolves a relative path against the
#' R working directory. Normalizing once at the boundary means every
#' consumer (messages, the cached `venv_dir` option, the setup scripts)
#' sees the same absolute path.
#'
#' `~` is expanded with [path.expand()], so it means what it means to
#' every other R file function in the session. A relative path is
#' resolved against [getwd()]. Symlinks are resolved when the path
#' exists, matching what [here::here()] returns for the default.
#'
#' @param path Character scalar. The directory need not exist.
#' @param arg Argument name used in the error message.
#'
#' @return Absolute path with forward slashes and no trailing slash.
#'
#' @keywords internal
#' @noRd
abs_path <- function(path, arg = "path") {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !nzchar(path)) {
    stop("`", arg, "` must be a single non-empty path", call. = FALSE)
  }
  path <- path.expand(path)
  # normalizePath() returns a nonexistent relative path unchanged, so
  # anchor it to the working directory first.
  if (!grepl("^(/|\\\\|[A-Za-z]:)", path)) {
    path <- file.path(getwd(), path)
  }
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  # A nonexistent path is returned as given, so tidy it by hand: collapse
  # repeated slashes (keeping a leading "//" for UNC paths) and drop any
  # trailing slash unless the path is a filesystem root ("/" or "C:/").
  path <- gsub("(?<!^)/+", "/", path, perl = TRUE)
  if (!grepl("^([A-Za-z]:)?/+$", path)) {
    path <- sub("/+$", "", path)
  }
  path
}
