#' Initialize the uv-managed Python virtual environment
#'
#' Ensures uv is installed at `uv_version`, then locks and syncs the
#' project's `.venv/` against `<pyproject_dir>/pyproject.toml`. If no
#' `pyproject.toml` exists at `pyproject_dir`, one is seeded from
#' pyro's bundled spec (templated with the project's directory
#' name) before lock and sync.
#'
#' The project's `pyproject.toml` is the source of truth. pyro
#' seeds it on first call but never modifies an existing toml — group
#' upserts are the responsibility of sibling-package wrappers via
#' [write_group_to_pyproject()].
#'
#' @param continue Optional. `"Y"` / `"n"` or `TRUE` / `FALSE` to
#'   bypass the interactive prompt. The same prompt covers both the uv
#'   install and the seed step (when the project has no `pyproject.toml`
#'   yet).
#' @param venv_dir Parent directory of `.venv/`. Defaults to
#'   [get_proj_dir()].
#' @param uv_version Version of uv to install. Defaults to
#'   `getOption("uv.version")`. When `NULL` (option unset), behavior
#'   is: if uv is already installed, its existing version is used (no
#'   reinstall); otherwise `"0.7.8"` is installed as a conservative
#'   fallback.
#' @param groups Character vector of dependency-group names from the
#'   project's `pyproject.toml` (e.g. `"reportifyr"`, `"presentifyr"`).
#'   When `NULL` (default), every declared group is installed via
#'   `uv sync --frozen --all-groups`. When supplied, uv runs in
#'   additive mode (`uv sync --frozen --inexact --group <g> ...`) so
#'   sibling fyr-package calls coexist without removing each other's
#'   deps. Group names are validated by uv; an unknown group surfaces
#'   uv's error.
#' @param pyproject_dir Directory containing the project's
#'   `pyproject.toml`. Defaults to `venv_dir`. Override for non-default
#'   project layouts (LLM agents, monorepos, closed-source projects
#'   with secret toml elsewhere). The directory must already exist;
#'   pyro will not create it.
#'
#' @return Invisibly `NULL`.
#'
#' @export
#'
#' @examples \dontrun{
#' initialize_python()                              # all groups
#' initialize_python(groups = "reportifyr")        # only reportifyr's group
#' initialize_python(groups = "presentifyr")       # only presentifyr's group
#' initialize_python(pyproject_dir = "~/proj")     # custom project root
#' }
initialize_python <- function(continue = NULL,
                              venv_dir = get_proj_dir(),
                              uv_version = getOption("uv.version"),
                              groups = NULL,
                              pyproject_dir = NULL) {
  log4r::debug(.le$logger, "Starting initialize_python function")

  if (is.null(pyproject_dir)) pyproject_dir <- venv_dir

  if (is.null(continue)) continue <- continue()
  if (is.logical(continue)) continue <- if (continue) "Y" else "n"

  if (tolower(continue) != "y") {
    if (continue == "n") {
      log4r::info(.le$logger, "User declined installation. No changes made.")
      message(
        "User declined installation of uv, Python, and Python dependencies.\n
        Full functionality will not be available."
      )
    } else {
      log4r::error(.le$logger, "Invalid response from user. Must enter Y or n.")
      stop("Must enter Y or n.")
    }
    log4r::debug(.le$logger, "Exiting initialize_python function")
    return(invisible(NULL))
  }

  log4r::info(.le$logger, "Installation confirmed.")

  if (is.null(getOption("venv_dir"))) {
    options("venv_dir" = venv_dir)
    log4r::info(.le$logger, "venv_dir option cached")
  }

  toml_path <- file.path(pyproject_dir, "pyproject.toml")
  if (!file.exists(toml_path)) {
    seed_pyproject(pyproject_dir, groups)
    message(paste0("Seeded ", toml_path, " from pyro's bundled spec."))
  }

  audit_pins(pyproject_dir, groups)

  uv_path <- get_uv_path(quiet = TRUE)
  log4r::info(.le$logger, paste0("uv path: ", uv_path))

  if (is.null(uv_version)) {
    if (!is.null(uv_path)) {
      uv_version <- get_uv_version(uv_path)
      log4r::info(
        .le$logger,
        paste0("Using installed uv version: ", uv_version)
      )
    } else {
      uv_version <- "0.7.8"
      log4r::info(.le$logger, "Using default uv version: 0.7.8")
    }
  }

  if (.Platform$OS.type == "windows") {
    cmd <- system.file("extdata/uv_setup.ps1", package = "pyro")
    log4r::info(.le$logger, "Windows platform detected, using PowerShell")
  } else {
    cmd <- system.file("extdata/uv_setup.sh", package = "pyro")
    log4r::info(.le$logger, "Unix-like platform detected, using bash script")
  }
  log4r::info(.le$logger, paste0("Setup script: ", cmd))

  venv_path <- file.path(venv_dir, ".venv")
  is_new_env <- !dir.exists(venv_path)

  log4r::info(.le$logger, paste0(
    "groups: ", if (is.null(groups)) "<all>" else paste(groups, collapse = ", ")
  ))

  if (.Platform$OS.type == "windows") {
    ps_args <- c(
      "-ExecutionPolicy", "Bypass", "-File", cmd,
      venv_dir, pyproject_dir, uv_version
    )
    if (!is.null(groups) && length(groups) > 0) {
      ps_args <- c(ps_args, "-Groups", groups)
    }
    log4r::info(.le$logger, paste0(
      "ps_args: ", paste(ps_args, collapse = ", ")
    ))
    result <- processx::run(command = "powershell.exe", args = ps_args)
  } else {
    sh_args <- c(venv_dir, pyproject_dir, uv_version)
    if (!is.null(groups) && length(groups) > 0) {
      sh_args <- c(sh_args, groups)
    }
    log4r::info(.le$logger, paste0(
      "sh_args: ", paste(sh_args, collapse = ", ")
    ))
    result <- processx::run(command = cmd, args = sh_args)
  }

  if (is_new_env) {
    log4r::info(.le$logger, paste("Virtual environment created at:", venv_path))
    message(paste("Created Python virtual environment at", venv_path))
  } else {
    log4r::info(.le$logger, paste("Virtual environment synced at:", venv_path))
  }

  message(result$stdout)

  log4r::debug(.le$logger, "Exiting initialize_python function")
  invisible(NULL)
}

#' Seed a project `pyproject.toml` from pyro's bundled spec
#'
#' Writes a minimal `[project]` table (`name = basename(proj_dir)`,
#' `requires-python` from bundled) and a `[dependency-groups]` table
#' containing the requested groups (or all bundled groups when
#' `groups = NULL`). Pins are copied verbatim from the bundled spec.
#'
#' Caller is responsible for ensuring the toml does not already exist.
#' Errors if `proj_dir` does not exist — seeding never creates the
#' project directory itself.
#'
#' @param proj_dir Project root directory. Must exist.
#' @param groups Character vector of group names to seed, or `NULL`
#'   for all bundled groups.
#'
#' @keywords internal
seed_pyproject <- function(proj_dir, groups = NULL) {
  bundled <- system.file("extdata", "pyproject.toml", package = "pyro")
  if (!nzchar(bundled) || !file.exists(bundled)) {
    stop("bundled pyproject.toml not found in pyro", call. = FALSE)
  }
  bundled_lines <- readLines(bundled, warn = FALSE)

  bundled_groups <- read_dep_groups(bundled_lines)
  if (is.null(bundled_groups)) {
    stop(
      "bundled pyproject.toml has no [dependency-groups] table",
      call. = FALSE
    )
  }

  selected <- if (is.null(groups)) {
    names(bundled_groups$entries)
  } else {
    missing <- setdiff(groups, names(bundled_groups$entries))
    if (length(missing)) {
      # Permit seeding with groups uv will validate later (e.g. user
      # supplied a group that exists in their wrappers but not in the
      # bundled reference). Seed with empty deps; uv add later.
      log4r::warn(.le$logger, paste0(
        "Seeding requested groups not in bundled spec: ",
        paste(missing, collapse = ", "),
        " — these will seed empty"
      ))
    }
    groups
  }

  requires_python <- read_requires_python(bundled_lines)
  proj_name <- sanitize_project_name(
    basename(normalizePath(proj_dir, mustWork = FALSE))
  )

  # uv requires project.version when [project] is present; "0.0.1" is a
  # stub satisfying the parser without implying the project is published.
  out <- c(
    "[project]",
    sprintf('name = "%s"', proj_name),
    'version = "0.0.1"'
  )
  if (!is.null(requires_python)) {
    out <- c(out, sprintf('requires-python = "%s"', requires_python))
  }
  out <- c(out, "", "[dependency-groups]")
  for (g in selected) {
    deps <- bundled_groups$entries[[g]] %||% character()
    out <- c(out, render_subgroup(g, deps))
  }

  if (!dir.exists(proj_dir)) {
    stop(
      "pyproject_dir does not exist: ", proj_dir,
      "\n  Create the directory first, or pass an existing path.",
      call. = FALSE
    )
  }
  writeLines(out, file.path(proj_dir, "pyproject.toml"))
  log4r::info(
    .le$logger,
    paste0("Seeded pyproject.toml at ", proj_dir, " with groups: ",
           paste(selected, collapse = ", "))
  )
}

#' Read `requires-python` from `[project]` table
#'
#' @keywords internal
read_requires_python <- function(lines) {
  m <- regmatches(
    lines,
    regexec('^\\s*requires-python\\s*=\\s*"([^"]+)"', lines)
  )
  hits <- m[lengths(m) == 2]
  if (length(hits) == 0) return(NULL)
  hits[[1]][2]
}

#' Sanitize a directory name into a valid PEP 508 project name
#'
#' uv accepts most strings but project names must match
#' `^[A-Za-z0-9._-]+$`. Replace anything outside that with `-` and
#' collapse leading non-alphanumeric.
#'
#' @keywords internal
sanitize_project_name <- function(name) {
  s <- gsub("[^A-Za-z0-9._-]+", "-", name)
  s <- sub("^[._-]+", "", s)
  if (!nzchar(s)) "project" else s
}

#' Prompt for installation confirmation
#'
#' Non-interactive sessions auto-confirm.
#'
#' @return Character `"Y"` or whatever the user typed.
#' @keywords internal
#' @noRd
continue <- function() {
  if (interactive()) {
    log4r::info(
      .le$logger,
      "Prompting user for confirmation to install uv, Python,
			and the pinned Python dependencies to your local files."
    )
    readline(
      "If uv, Python, and Python dependencies are not installed, this
			\nwill install them. If your project has no pyproject.toml,
			\none will be created at the project root.
			\nAre you sure you want to continue? [Y/n]\n"
    )
  } else {
    log4r::info(
      .le$logger,
      "Non-interactive session detected, proceeding with installation."
    )
    "Y"
  }
}
