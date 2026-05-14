#' Ensure a dependency group is present in the project's `pyproject.toml`
#'
#' Idempotent merge helper called by sibling-package wrappers
#' (reportifyr, presentifyr) and third-party apps to wire their Python
#' dependency group into the project's `pyproject.toml`.
#'
#' Merge semantics by case:
#' \describe{
#'   \item{No `pyproject.toml`}{No-op, returns `FALSE`. Seeding is
#'     [initialize_python()]'s job; this helper composes with it but
#'     does not duplicate it.}
#'   \item{No `[dependency-groups]` table}{Append the table containing
#'     `name`. Returns `TRUE`.}
#'   \item{Table exists, no `name` subgroup}{Append the subgroup with
#'     `deps`. Returns `TRUE`.}
#'   \item{Subgroup exists, dep names match}{Per-dep version comparison.
#'     If versions match: no-op, returns `FALSE`. If versions differ:
#'     keep the user's pin (do not overwrite), emit a one-line message
#'     per diff. Returns `FALSE`.}
#'   \item{Subgroup exists, dep names differ}{Add any deps missing from
#'     the project's group with the spec's pins. Never remove deps the
#'     user added. Returns `TRUE`.}
#' }
#'
#' The "spec" is pyro's bundled `pyproject.toml` for fyr-blessed
#' groups (when `deps = NULL`), or the caller-supplied `deps` for
#' third-party apps.
#'
#' @param name Character group name (e.g. `"reportifyr"`).
#' @param deps Optional character vector of dependency strings
#'   (e.g. `c("pillow==11.1.0", "requests==2.31.0")`). When `NULL`
#'   (default), the bundled `pyproject.toml` is consulted for `name`;
#'   if `name` is not bundled, an error is raised.
#' @param pyproject_dir Directory containing the project's
#'   `pyproject.toml`. Defaults to [get_proj_dir()].
#'
#' @return Invisibly, `TRUE` if the toml was mutated, `FALSE` otherwise.
#'
#' @export
#'
#' @examples \dontrun{
#' # fyr-blessed group: pins read from bundled spec
#' write_group_to_pyproject("reportifyr")
#'
#' # third-party app: pins supplied explicitly
#' write_group_to_pyproject("myapp", deps = c("requests==2.31.0"))
#' }
write_group_to_pyproject <- function(name,
                                     deps = NULL,
                                     pyproject_dir = get_proj_dir()) {
  if (!grepl("^[A-Za-z_][A-Za-z0-9_-]*$", name)) {
    stop(
      "`name` must match TOML bare-key pattern ",
      "[A-Za-z_][A-Za-z0-9_-]*; got: '", name, "'",
      call. = FALSE
    )
  }
  toml_path <- file.path(pyproject_dir, "pyproject.toml")
  if (!file.exists(toml_path)) {
    log4r::debug(
      .le$logger,
      paste0("No pyproject.toml at ", pyproject_dir, "; merge helper no-op")
    )
    return(invisible(FALSE))
  }

  if (is.null(deps)) {
    deps <- bundled_group_deps(name)
    if (is.null(deps)) {
      stop(
        "group '", name, "' is not in pyro's bundled spec; ",
        "supply `deps` explicitly for third-party groups",
        call. = FALSE
      )
    }
  }

  lines <- readLines(toml_path, warn = FALSE)
  groups <- read_dep_groups(lines)

  changed <- FALSE
  if (is.null(groups)) {
    # Case 1: no [dependency-groups] table at all
    new_lines <- append_dep_groups_table(lines, name, deps)
    writeLines(new_lines, toml_path)
    log4r::info(
      .le$logger,
      paste0("Added [dependency-groups] table with '", name, "' to ", toml_path)
    )
    changed <- TRUE
  } else if (is.null(groups$entries[[name]])) {
    # Case 2: table exists, no `name` subgroup
    new_lines <- append_subgroup(lines, groups, name, deps)
    writeLines(new_lines, toml_path)
    log4r::info(
      .le$logger,
      paste0("Added '", name, "' group to ", toml_path)
    )
    changed <- TRUE
  } else {
    # Subgroup exists. Merge by dep-name; respect user pins on conflict.
    existing <- groups$entries[[name]]
    merged <- merge_deps(existing, deps)
    if (!identical(sort(merged), sort(existing))) {
      # Case 4a: structural diff — splice in merged set
      new_lines <- replace_subgroup(lines, groups, name, merged)
      writeLines(new_lines, toml_path)
      log4r::info(
        .le$logger,
        paste0("Updated '", name, "' group in ", toml_path)
      )
      changed <- TRUE
    }
    # Case 3 (semantic match) and case 4b (version-only diff) fall
    # through with changed = FALSE. Drift surfacing for case 4b is
    # audit_pins()'s job, called from initialize_python().
  }

  invisible(changed)
}

#' Read the bundled `pyproject.toml` and return the deps for one group
#'
#' @param name Group name.
#'
#' @return Character vector of dependency strings, or `NULL` if `name`
#'   is not in the bundled spec.
#'
#' @keywords internal
bundled_group_deps <- function(name) {
  bundled <- system.file("extdata", "pyproject.toml", package = "pyro")
  if (!nzchar(bundled) || !file.exists(bundled)) {
    stop("bundled pyproject.toml not found in pyro", call. = FALSE)
  }
  groups <- read_dep_groups(readLines(bundled, warn = FALSE))
  if (is.null(groups)) return(NULL)
  groups$entries[[name]]
}

#' Parse `[dependency-groups]` from a TOML file's lines
#'
#' Returns a list with `header_idx` (line index of `[dependency-groups]`),
#' `block_end` (line index of last line in the block, exclusive of the
#' next section header), and `entries` (named list mapping group name to
#' character vector of dependency strings). Returns `NULL` if the table
#' is not present.
#'
#' Only handles the canonical `[dependency-groups]` table form with
#' arrays of strings — both inline (`name = ["a", "b"]`) and multi-line
#' (`name = [\n  "a",\n  "b",\n]`). Other TOML constructs in the file
#' are preserved verbatim by the splice helpers; this parser only
#' inspects the dep-groups block.
#'
#' @param lines Character vector of file lines.
#'
#' @keywords internal
read_dep_groups <- function(lines) {
  hdr_re <- "^\\s*\\[dependency-groups\\]\\s*(#.*)?$"
  hdr_idx <- which(grepl(hdr_re, lines))
  if (length(hdr_idx) == 0) return(NULL)
  start <- hdr_idx[1]

  # Find next section header (root or nested table) after start.
  if (start < length(lines)) {
    after <- (start + 1):length(lines)
    next_hdr <- which(grepl("^\\s*\\[", lines[after]))
    block_end <- if (length(next_hdr)) {
      start + next_hdr[1] - 1
    } else {
      length(lines)
    }
  } else {
    block_end <- length(lines)
  }

  block <- if (start + 1 <= block_end) {
    lines[(start + 1):block_end]
  } else {
    character()
  }
  entries <- parse_group_entries(block)

  list(header_idx = start, block_end = block_end, entries = entries)
}

#' Parse the body of a `[dependency-groups]` block into a named list of
#' character vectors.
#'
#' @param block Character vector of lines inside the table (after the
#'   header, up to the next section header).
#'
#' @keywords internal
parse_group_entries <- function(block) {
  entries <- list()
  i <- 1
  n <- length(block)
  entry_re <- "^\\s*([A-Za-z_][A-Za-z0-9_-]*)\\s*=\\s*\\[(.*)$"
  while (i <= n) {
    line <- block[i]
    m <- regmatches(line, regexec(entry_re, line))[[1]]
    if (length(m) == 3) {
      name <- m[2]
      tail <- m[3]
      # Inline form: closing bracket on same line.
      close_inline <- close_bracket_pos(tail)
      if (close_inline > 0) {
        body <- substr(tail, 1, close_inline - 1)
        entries[[name]] <- extract_quoted(body)
        i <- i + 1
        next
      }
      # Multi-line form: accumulate until line containing `]`.
      body_acc <- tail
      j <- i + 1
      while (j <= n && close_bracket_pos(block[j]) <= 0) {
        body_acc <- paste(body_acc, block[j], sep = "\n")
        j <- j + 1
      }
      if (j <= n) {
        close_line <- block[j]
        close_pos <- close_bracket_pos(close_line)
        body_acc <- paste(
          body_acc,
          substr(close_line, 1, close_pos - 1),
          sep = "\n"
        )
        i <- j + 1
      } else {
        # Unterminated — treat what we have, advance past block.
        i <- j
      }
      entries[[name]] <- extract_quoted(body_acc)
    } else {
      i <- i + 1
    }
  }
  entries
}

#' Find the offset of the first `]` outside any TOML-quoted span
#'
#' Distinguishes the array-close bracket from `]` that appears inside
#' quoted dep strings — e.g. PEP 508 extras like
#' `"requests[security]==2.31.0"`. Tracks both `"..."` (with backslash
#' escapes) and `'...'` (TOML literal — no escapes per spec).
#'
#' @return 1-based offset of the first unquoted `]`, or `-1L` if none.
#'
#' @keywords internal
close_bracket_pos <- function(s) {
  if (!nzchar(s)) return(-1L)
  chars <- strsplit(s, "", fixed = TRUE)[[1]]
  in_double <- FALSE
  in_single <- FALSE
  escape <- FALSE
  for (i in seq_along(chars)) {
    ch <- chars[i]
    if (escape) {
      escape <- FALSE
      next
    }
    if (in_double) {
      if (ch == "\\") escape <- TRUE
      else if (ch == '"') in_double <- FALSE
    } else if (in_single) {
      if (ch == "'") in_single <- FALSE
    } else if (ch == '"') {
      in_double <- TRUE
    } else if (ch == "'") {
      in_single <- TRUE
    } else if (ch == "]") {
      return(i)
    }
  }
  -1L
}

#' Extract quoted strings from a TOML array body
#'
#' Supports both double-quoted (`"..."`) and single-quoted (`'...'`) TOML
#' string literals.
#'
#' @keywords internal
extract_quoted <- function(s) {
  m <- gregexpr("(?:(\"([^\"\\\\]|\\\\.)*\")|'[^']*')", s, perl = TRUE)
  toks <- regmatches(s, m)[[1]]
  if (length(toks) == 0) return(character())
  # Strip surrounding quotes; do not interpret escapes (deps are simple
  # ASCII pin strings — `pkg==1.2.3`, optionally with markers).
  substr(toks, 2, nchar(toks) - 1)
}

#' Merge spec deps into existing project deps
#'
#' For each spec dep, if its package name is missing from the project's
#' group, add the spec entry. If present with a different version pin,
#' silently keep the project's pin (drift surfacing is [audit_pins()]'s
#' job). Project deps not in the spec are preserved.
#'
#' @keywords internal
merge_deps <- function(existing, spec) {
  existing_names <- pkg_name_of(existing)
  spec_names <- pkg_name_of(spec)
  out <- existing
  for (i in seq_along(spec)) {
    if (is.na(match(spec_names[i], existing_names))) {
      out <- c(out, spec[i])
    }
  }
  out
}

#' Extract the package name from a PEP 508-ish pin string
#'
#' Handles `pkg`, `pkg==X.Y.Z`, `pkg>=X`, `pkg[extra]==X`, etc. Strips
#' anything after the first occurrence of `[`, `=`, `<`, `>`, `!`, `~`,
#' `;`, or whitespace.
#'
#' @keywords internal
pkg_name_of <- function(deps) {
  sub("[\\[=<>!~; ].*$", "", deps, perl = TRUE)
}

#' Render a `[dependency-groups]` subgroup in canonical multi-line form
#'
#' @keywords internal
render_subgroup <- function(name, deps) {
  c(
    paste0(name, " = ["),
    paste0("    \"", deps, "\","),
    "]"
  )
}

#' Append a fresh `[dependency-groups]` table at end of file
#'
#' @keywords internal
append_dep_groups_table <- function(lines, name, deps) {
  # Ensure separation from prior content.
  sep <- if (length(lines) > 0 && nzchar(lines[length(lines)])) "" else NULL
  c(lines, sep, "[dependency-groups]", render_subgroup(name, deps))
}

#' Append a subgroup inside an existing `[dependency-groups]` table
#'
#' @keywords internal
append_subgroup <- function(lines, groups, name, deps) {
  insert_at <- groups$block_end
  before <- lines[seq_len(insert_at)]
  after <- if (insert_at < length(lines)) {
    lines[(insert_at + 1):length(lines)]
  } else {
    character()
  }
  # Trim trailing blank from `before` so we control spacing around insert.
  while (length(before) && !nzchar(before[length(before)])) {
    before <- before[-length(before)]
  }
  c(before, render_subgroup(name, deps), "", after)
}

#' Replace an existing subgroup's body with new deps
#'
#' Locates the subgroup by header line within the dep-groups block,
#' splices in the canonical render. Lines outside the subgroup are
#' preserved byte-for-byte.
#'
#' @keywords internal
replace_subgroup <- function(lines, groups, name, deps) {
  block_start <- groups$header_idx + 1
  block_end <- groups$block_end
  if (block_start > block_end) {
    # Nothing in block — fall back to append.
    return(append_subgroup(lines, groups, name, deps))
  }
  block <- lines[block_start:block_end]
  entry_re <- paste0(
    "^\\s*", name, "\\s*=\\s*\\["
  )
  hits <- which(grepl(entry_re, block))
  if (length(hits) == 0) {
    return(append_subgroup(lines, groups, name, deps))
  }
  sub_start <- hits[1]
  # Determine subgroup end: same line for inline arrays, else first line
  # after sub_start that contains `]`.
  if (close_bracket_pos(block[sub_start]) > 0) {
    sub_end <- sub_start
  } else {
    rest <- if (sub_start < length(block)) {
      (sub_start + 1):length(block)
    } else {
      integer()
    }
    closes <- which(vapply(
      block[rest], function(x) close_bracket_pos(x) > 0, logical(1)
    ))
    sub_end <- if (length(closes)) rest[closes[1]] else length(block)
  }
  before_block <- if (sub_start > 1) {
    block[seq_len(sub_start - 1)]
  } else {
    character()
  }
  after_block <- if (sub_end < length(block)) {
    block[(sub_end + 1):length(block)]
  } else {
    character()
  }
  new_block <- c(before_block, render_subgroup(name, deps), after_block)

  before_file <- if (block_start > 1) {
    lines[seq_len(block_start - 1)]
  } else {
    character()
  }
  after_file <- if (block_end < length(lines)) {
    lines[(block_end + 1):length(lines)]
  } else {
    character()
  }
  c(before_file, new_block, after_file)
}
