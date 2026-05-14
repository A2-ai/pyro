#' pyro: uv-backed Python Environment Helpers for the fyr Ecosystem
#'
#' Provides uv-backed Python virtual-environment management used across
#' the fyr ecosystem (reportifyr, presentifyr). Wraps the uv CLI via
#' processx for locating the uv binary, bootstrapping a `.venv/`,
#' installing pinned Python dependencies, and running Python scripts.
#'
#' @section Public API:
#' \itemize{
#'   \item \code{\link{initialize_python}}: Bootstraps uv (if missing),
#'   creates a `.venv/`, and installs the requested Python packages.
#'   \item \code{\link{get_venv_uv_paths}}: Resolves the paths to the uv
#'   binary and the project's `.venv/` directory. Used by host packages
#'   before invoking Python scripts.
#'   \item \code{\link{write_group_to_pyproject}}: Idempotent merge
#'   helper for sibling and third-party packages to wire their Python
#'   dependency group into the project's `pyproject.toml`.
#' }
#'
#' @section Internal helpers (exported for sibling packages):
#' These are declared with `@keywords internal` and are not a stable
#' public API. They are listed in NAMESPACE so sibling fyr packages can
#' call them directly without triple-colon.
#' \itemize{
#'   \item \code{\link{get_proj_dir}}: Project-root resolver (reads
#'   `getOption("venv_dir")` then falls back to `here::here()`).
#'   \item \code{\link{get_uv_path}}, \code{\link{get_uv_version}}: uv
#'   binary resolution and version detection.
#'   \item \code{\link{run_python_script}}: invokes a Python script
#'   inside the uv-managed venv via processx.
#' }
#'
#' @section Logging:
#' pyro writes log lines through an internal `log4r` logger whose
#' threshold is read from `getOption("pyro.verbose", "WARN")` on
#' each emission. To change verbosity, simply set the option:
#' \preformatted{options(pyro.verbose = "DEBUG")}
#' No reload or toggle call is required; the next log call reflects the
#' new level. Use `withr::with_options(list(pyro.verbose = "DEBUG"),
#' \{...\})` to scope a verbose level to a single block.
#'
#' @name pyro
#' @importFrom rlang %||%
"_PACKAGE"
