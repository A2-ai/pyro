#' Resolve the project root directory
#'
#' Single canonical resolver for "where does this project live?". Used as
#' the default for `pyproject_dir` and `venv_dir` in
#' [initialize_python()], and as a base for sibling-package wrappers that
#' need to locate the project's `pyproject.toml`.
#'
#' Resolution order:
#' \enumerate{
#'   \item `getOption("venv_dir")` if set (cached project root, written by
#'     prior calls to [initialize_python()]).
#'   \item [here::here()] otherwise.
#' }
#'
#' @return Absolute path to the project root.
#'
#' @export
#'
#' @examples \dontrun{
#' get_proj_dir()
#' }
get_proj_dir <- function() {
  getOption("venv_dir") %||% here::here()
}
