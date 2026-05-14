## Covers the merge cases for write_group_to_pyproject():
##   - missing toml -> no-op, FALSE
##   - no [dependency-groups] table -> append, TRUE
##   - table exists, group missing -> append subgroup, TRUE
##   - group present, semantically matches -> no-op, FALSE
##   - group present, version-only diff -> keep user's pin, FALSE, message
##   - group present, structural diff -> add missing dep, TRUE

write_toml <- function(dir, lines) {
  path <- file.path(dir, "pyproject.toml")
  writeLines(lines, path)
  path
}

test_that("no toml: no-op, returns FALSE", {
  proj <- tempfile()
  dir.create(proj)
  expect_false(write_group_to_pyproject(
    "reportifyr",
    deps = c("pillow==11.1.0"),
    pyproject_dir = proj
  ))
})

test_that("no [dependency-groups] table: appends, returns TRUE", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    'requires-python = ">=3.12"'
  ))

  changed <- write_group_to_pyproject(
    "reportifyr",
    deps = c("pillow==11.1.0", "pyyaml==6.0.2"),
    pyproject_dir = proj
  )
  expect_true(changed)

  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("\\[dependency-groups\\]", lines)))
  expect_true(any(grepl("^reportifyr = \\[", lines)))
  expect_true(any(grepl("pillow==11.1.0", lines)))
  expect_true(any(grepl("pyyaml==6.0.2", lines)))
})

test_that("table exists, group missing: appends subgroup, returns TRUE", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    'presentifyr = ["python-pptx==1.0.2"]'
  ))

  changed <- write_group_to_pyproject(
    "reportifyr",
    deps = c("pillow==11.1.0"),
    pyproject_dir = proj
  )
  expect_true(changed)

  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("^presentifyr = \\[", lines)))
  expect_true(any(grepl("^reportifyr = \\[", lines)))
})

test_that("group present, semantically matches: no-op, returns FALSE", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    "reportifyr = [",
    '    "pillow==11.1.0",',
    '    "pyyaml==6.0.2",',
    "]"
  ))

  before <- readLines(file.path(proj, "pyproject.toml"))
  changed <- write_group_to_pyproject(
    "reportifyr",
    deps = c("pillow==11.1.0", "pyyaml==6.0.2"),
    pyproject_dir = proj
  )
  expect_false(changed)
  expect_identical(before, readLines(file.path(proj, "pyproject.toml")))
})

test_that("group present, version-only diff: keep user pin, FALSE, silent", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    "reportifyr = [",
    '    "pillow==10.0.0",',
    "]"
  ))

  # Drift surfacing is audit_pins()'s job; the writer is silent on 4b.
  expect_no_message({
    changed <- write_group_to_pyproject(
      "reportifyr",
      deps = c("pillow==11.1.0"),
      pyproject_dir = proj
    )
  })
  expect_false(changed)

  # User's pin preserved verbatim.
  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("pillow==10.0.0", lines)))
  expect_false(any(grepl("pillow==11.1.0", lines)))
})

test_that("group present, structural diff: adds missing dep, TRUE", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    "reportifyr = [",
    '    "pillow==11.1.0",',
    "]"
  ))

  changed <- write_group_to_pyproject(
    "reportifyr",
    deps = c("pillow==11.1.0", "pyyaml==6.0.2"),
    pyproject_dir = proj
  )
  expect_true(changed)

  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("pillow==11.1.0", lines)))
  expect_true(any(grepl("pyyaml==6.0.2", lines)))
})

test_that("structural diff preserves user-added deps not in spec", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    "reportifyr = [",
    '    "pillow==11.1.0",',
    '    "user-extra==1.0.0",',
    "]"
  ))

  changed <- write_group_to_pyproject(
    "reportifyr",
    deps = c("pillow==11.1.0", "pyyaml==6.0.2"),
    pyproject_dir = proj
  )
  expect_true(changed)

  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("user-extra==1.0.0", lines)))
  expect_true(any(grepl("pyyaml==6.0.2", lines)))
})

test_that("inline-array group form is parsed correctly", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    'reportifyr = ["pillow==11.1.0", "pyyaml==6.0.2"]'
  ))

  changed <- write_group_to_pyproject(
    "reportifyr",
    deps = c("pillow==11.1.0", "pyyaml==6.0.2"),
    pyproject_dir = proj
  )
  expect_false(changed)
})

test_that("bundled lookup works when deps = NULL for fyr-blessed group", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"'
  ))

  # 'reportifyr' is in pyro's bundled spec; deps inferred.
  changed <- write_group_to_pyproject("reportifyr", pyproject_dir = proj)
  expect_true(changed)

  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("^reportifyr = \\[", lines)))
})

test_that("inline array with PEP 508 extras parses without truncation", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[dependency-groups]",
    'reportifyr = ["requests[security]==2.31.0"]'
  ))

  changed <- write_group_to_pyproject(
    "reportifyr",
    deps = c("requests[security]==2.31.0"),
    pyproject_dir = proj
  )
  expect_false(changed)

  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("requests\\[security\\]==2\\.31\\.0", lines)))
})

test_that("multi-line array with PEP 508 extras parses without truncation", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[dependency-groups]",
    "reportifyr = [",
    '    "requests[security]==2.31.0",',
    '    "pillow==11.1.0",',
    "]"
  ))

  changed <- write_group_to_pyproject(
    "reportifyr",
    deps = c("requests[security]==2.31.0", "pillow==11.1.0"),
    pyproject_dir = proj
  )
  expect_false(changed)

  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("requests\\[security\\]==2\\.31\\.0", lines)))
  expect_true(any(grepl("pillow==11\\.1\\.0", lines)))
})

test_that("structural diff with bracket-extras user pin: file stays valid", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[dependency-groups]",
    "reportifyr = [",
    '    "requests[security]==2.31.0",',
    '    "pillow==11.1.0",',
    "]"
  ))

  # Spec adds pyyaml; user's bracket-extras pin must survive the splice.
  changed <- write_group_to_pyproject(
    "reportifyr",
    deps = c("pillow==11.1.0", "pyyaml==6.0.2"),
    pyproject_dir = proj
  )
  expect_true(changed)

  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("requests\\[security\\]==2\\.31\\.0", lines)))
  expect_true(any(grepl("pyyaml==6\\.0\\.2", lines)))
  # Exactly one closing `]` line — no orphaned trailing artifact.
  expect_equal(sum(trimws(lines) == "]"), 1L)
})

test_that("replace_subgroup preserves sibling subgroup and trailing tables byte-for-byte", {
  proj <- tempfile()
  dir.create(proj)
  before <- c(
    "[project]",
    'name = "test"',
    'version = "1.2.3"',
    'description = "important"',
    "",
    "[dependency-groups]",
    "presentifyr = [",
    '    "python-pptx==1.0.2",',
    "]",
    "reportifyr = [",
    '    "pillow==10.0.0",',
    "]",
    "",
    "[tool.uv]",
    'index = "https://pypi.org/simple"'
  )
  write_toml(proj, before)

  write_group_to_pyproject(
    "reportifyr",
    deps = c("pillow==11.1.0", "pyyaml==6.0.2"),
    pyproject_dir = proj
  )

  after <- readLines(file.path(proj, "pyproject.toml"))
  # [project] block intact
  expect_equal(after[1:5], before[1:5])
  # presentifyr subgroup intact
  expect_equal(after[7:9], before[7:9])
  # [tool.uv] block intact at end of file
  n <- length(after)
  expect_equal(after[(n - 1):n], before[14:15])
})

test_that("mixed structural + version diff: missing dep added, drifted pin preserved", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[dependency-groups]",
    "reportifyr = [",
    '    "pillow==10.0.0",',
    '    "user-extra==1.0.0",',
    "]"
  ))
  changed <- write_group_to_pyproject(
    "reportifyr",
    deps = c("pillow==11.1.0", "pyyaml==6.0.2"),
    pyproject_dir = proj
  )
  expect_true(changed)

  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("pillow==10\\.0\\.0", lines)))
  expect_false(any(grepl("pillow==11\\.1\\.0", lines)))
  expect_true(any(grepl("user-extra==1\\.0\\.0", lines)))
  expect_true(any(grepl("pyyaml==6\\.0\\.2", lines)))
})

test_that("invalid name (TOML bare-key violation) errors loudly", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c('[project]', 'name = "test"'))

  expect_error(
    write_group_to_pyproject(
      "foo.bar",
      deps = c("pillow==11.1.0"),
      pyproject_dir = proj
    ),
    "bare-key pattern"
  )
  expect_error(
    write_group_to_pyproject(
      "1leading-digit",
      deps = c("pillow==11.1.0"),
      pyproject_dir = proj
    ),
    "bare-key pattern"
  )
})

test_that("unknown group with deps = NULL errors", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c('[project]', 'name = "test"'))

  expect_error(
    write_group_to_pyproject("notabundled", pyproject_dir = proj),
    "not in pyro's bundled spec"
  )
})
