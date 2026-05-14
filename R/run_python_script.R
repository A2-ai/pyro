#' Run a Python script inside the uv-managed venv
#'
#' Shells out to uv via [processx::run()] with the venv's `VIRTUAL_ENV`
#' and (optionally) a caller-supplied `PYTHONPATH`. pyro does not
#' persist subprocess output to any file — routing of the Python
#' subprocess' stderr is entirely the caller's concern. Supply
#' `stderr_callback` to capture, reformat, or filter stderr lines; wrap
#' this call in `tryCatch()` if you want to act on a subprocess crash.
#'
#' @param uv_path Path to the uv executable.
#' @param args Arguments to pass to uv (e.g., `c("run", "-m", "my_cli")`).
#' @param venv_path Path to the `.venv/` directory (sets `VIRTUAL_ENV`).
#' @param script_name Human-readable label used in the error message.
#' @param pythonpath Optional directory to expose as `PYTHONPATH` (for
#'   host packages whose Python modules live under their `inst/python/`).
#' @param stderr_callback Optional `function(chunk, proc)` callback passed
#'   to [processx::run()] as `stderr_callback`. If `NULL`, stderr is
#'   streamed to the console unchanged via `cat()`.
#' @param verbose_env Optional name of an environment variable to surface
#'   to the subprocess (for example, the caller's verbosity control).
#'
#' @return The result from [processx::run()].
#'
#' @examples \dontrun{
#' paths <- pyro::get_venv_uv_paths()
#' pyro::run_python_script(
#'   uv_path     = paths$uv,
#'   venv_path   = paths$venv,
#'   args        = c("run", "-m", "my_module"),
#'   script_name = "my_module"
#' )
#' }
#'
#' @export
run_python_script <- function(uv_path,
                              args,
                              venv_path,
                              script_name,
                              pythonpath = NULL,
                              stderr_callback = NULL,
                              verbose_env = NULL) {
  env_vars <- c("current", VIRTUAL_ENV = venv_path)
  if (!is.null(verbose_env) && nzchar(verbose_env)) {
    env_vars <- c(
      env_vars,
      stats::setNames(Sys.getenv(verbose_env, unset = "WARN"), verbose_env)
    )
  }
  if (!is.null(pythonpath) && nzchar(pythonpath)) {
    env_vars <- c(env_vars, PYTHONPATH = pythonpath)
  }

  cb <- stderr_callback %||% default_stderr_callback

  tryCatch(
    processx::run(
      command         = uv_path,
      args            = args,
      env             = env_vars,
      stderr_callback = cb,
      error_on_status = TRUE
    ),
    error = function(e) {
      stop(paste0(script_name, " failed."), call. = FALSE)
    }
  )
}

default_stderr_callback <- function(chunk, proc) {
  cat(chunk)
}
