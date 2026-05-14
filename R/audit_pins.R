#' Report drift between project pyproject pins and pyro's bundled spec
#'
#' Reads `<pyproject_dir>/pyproject.toml` and, for groups in scope,
#' emits one message per dep whose pin differs from pyro's bundled
#' spec.
#'
#' Groups in the project toml that aren't in the bundled spec (e.g.
#' third-party app groups, user-defined groups) are skipped silently.
#' Deps present in bundled but missing from the project are also skipped.
#'
#' Cross-group pin conflicts (e.g. reportifyr pins `pillow==10.0.0`,
#' presentifyr pins `pillow==11.1.0`) are not reported here either:
#' uv's lock pass spans the whole toml and surfaces "no solution found".
#'
#' Called automatically by [initialize_python()] before sync, so drift
#' surfaces on every init regardless of how the wrapper structured its
#' setup.
#'
#' @param pyproject_dir Directory containing the project's
#'   `pyproject.toml`. Defaults to [get_proj_dir()].
#' @param groups Optional character vector of group names to scope the
#'   audit to. When `NULL` (default), every bundled-known group present
#'   in the project toml is audited. When supplied, drift in groups
#'   outside this set is silenced — a sibling group's drift will
#'   surface the next init that targets it, or via uv's resolver when
#'   the drift causes a cross-group conflict.
#'
#' @return Invisibly `NULL`. Side effect is one `message()` per
#'   drifted dep.
#'
#' @keywords internal
audit_pins <- function(pyproject_dir = get_proj_dir(), groups = NULL) {
  toml_path <- file.path(pyproject_dir, "pyproject.toml")
  if (!file.exists(toml_path)) return(invisible(NULL))

  parsed <- read_dep_groups(readLines(toml_path, warn = FALSE))
  if (is.null(parsed) || length(parsed$entries) == 0) {
    return(invisible(NULL))
  }

  group_names <- names(parsed$entries)
  if (!is.null(groups)) {
    group_names <- intersect(group_names, groups)
  }

  for (group_name in group_names) {
    bundled <- bundled_group_deps(group_name)
    if (is.null(bundled)) next

    project_pins <- parsed$entries[[group_name]]
    project_names <- pkg_name_of(project_pins)
    bundled_names <- pkg_name_of(bundled)

    for (i in seq_along(bundled)) {
      pos <- match(bundled_names[i], project_names)
      if (is.na(pos)) next
      if (project_pins[pos] != bundled[i]) {
        message(sprintf(
          "pyro: '%s' group has %s; bundled spec uses %s",
          group_name, project_pins[pos], bundled[i]
        ))
      }
    }
  }

  invisible(NULL)
}
