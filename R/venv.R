#' Resolve paths to the uv binary and the project's `.venv` directory
#'
#' Looks up the project root via [get_proj_dir()] (which reads
#' `getOption("venv_dir")`, falling back to [here::here()]) and caches
#' the resolved root in `options("venv_dir")` so subsequent calls are
#' cheap.
#'
#' @return Named list with `uv` (path to uv) and `venv` (path to the
#'   `.venv/` directory).
#'
#' @export
#'
#' @examples \dontrun{
#' get_venv_uv_paths()
#' }
get_venv_uv_paths <- function() {
  if (is.null(getOption("venv_dir"))) {
    log4r::info(.le$logger, "Setting options('venv_dir') to project root.")
    message("Setting options('venv_dir') to project root.")
    options("venv_dir" = get_proj_dir())
  }
  venv_path <- file.path(getOption("venv_dir"), ".venv")

  if (!dir.exists(venv_path)) {
    log4r::error(
      .le$logger,
      "Virtual environment not found. Please initialize with initialize_python."
    )
    stop("Create virtual environment with initialize_python")
  }

  uv_path <- get_uv_path()
  if (is.null(uv_path)) {
    log4r::error(
      .le$logger,
      "uv not found. Please install with initialize_python"
    )
    stop("Please install uv with initialize_python")
  }

  list(uv = uv_path, venv = venv_path)
}
