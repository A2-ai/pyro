#' Locate the uv binary
#'
#' Searches `PATH` first, then known install locations
#' (`~/.local/bin/uv`, `~/.cargo/bin/uv`) cross-platform. Respects the
#' `HOME` environment variable for test isolation.
#'
#' Use this to detect whether uv is installed without triggering an
#' install. [initialize_python()] performs the install; this helper is
#' a pure lookup.
#'
#' @param quiet If `TRUE`, suppress the log message when uv is not found.
#'
#' @return Path to the uv executable, or `NULL` if none is found.
#'
#' @export
#'
#' @examples \dontrun{
#' uv_path <- get_uv_path()
#' if (is.null(uv_path)) message("uv not installed yet")
#' }
get_uv_path <- function(quiet = FALSE) {
  path_env <- Sys.getenv("PATH")
  uv_in_path <- if (nzchar(path_env)) Sys.which("uv") else ""

  home_env <- Sys.getenv("HOME")
  home_dir <- if (nzchar(home_env)) home_env else path.expand("~")

  if (.Platform$OS.type == "windows") {
    uv_paths <- c(
      file.path(home_dir, ".local", "bin", "uv.exe"),
      file.path(home_dir, ".local", "bin", "uv"),
      file.path(home_dir, ".cargo", "bin", "uv.exe"),
      file.path(home_dir, ".cargo", "bin", "uv")
    )
  } else {
    uv_paths <- c(
      file.path(home_dir, ".local", "bin", "uv"),
      file.path(home_dir, ".cargo", "bin", "uv")
    )
  }

  if (nzchar(uv_in_path)) {
    uv_paths <- c(uv_in_path, uv_paths)
  }

  uv_paths <- uv_paths[nzchar(uv_paths) & file.exists(uv_paths)]
  uv_path <- if (length(uv_paths)) normalizePath(uv_paths[[1]]) else NULL

  if (!quiet && is.null(uv_path)) {
    log4r::warn(
      .le$logger,
      "uv not found. Please install with initialize_python"
    )
  }
  uv_path
}

#' Get the installed version of uv
#'
#' Shells out to `uv --version` and parses the result. Useful for
#' diagnostics and for callers that need to gate behavior on the uv
#' version (e.g. only set a flag introduced in a specific release).
#'
#' @param uv_path Path to the uv executable. Typically obtained from
#'   [get_uv_path()].
#'
#' @return Character scalar of the uv version (e.g., `"0.7.8"`).
#'
#' @export
#'
#' @examples \dontrun{
#' uv_path <- get_uv_path()
#' if (!is.null(uv_path)) get_uv_version(uv_path)
#' }
get_uv_version <- function(uv_path) {
  result <- processx::run(uv_path, "--version")
  # output should be "uv version (commit date)"
  trimws(strsplit(result$stdout, " ")[[1]][2])
}
