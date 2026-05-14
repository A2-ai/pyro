## audit_pins(): pure-read drift reporter. Compares each project group's
## pins against pyro's bundled spec, emits one message per drifted
## dep. Silent when matched. Skips groups not in bundled.

write_toml <- function(dir, lines) {
  writeLines(lines, file.path(dir, "pyproject.toml"))
}

test_that("no toml: silent, returns NULL invisibly", {
  proj <- tempfile()
  dir.create(proj)
  expect_no_message(audit_pins(proj))
  expect_null(audit_pins(proj))
})

test_that("no [dependency-groups] table: silent", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c('[project]', 'name = "test"'))
  expect_no_message(audit_pins(proj))
})

test_that("groups match bundled exactly: silent", {
  proj <- tempfile()
  dir.create(proj)
  # Use bundled-matching pins for reportifyr.
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    "reportifyr = [",
    '    "python-docx==1.1.2",',
    '    "pyyaml==6.0.2",',
    '    "pillow==11.1.0",',
    "]"
  ))
  expect_no_message(audit_pins(proj))
})

test_that("version-only diff: emits one message per drifted dep", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    "reportifyr = [",
    '    "python-docx==1.1.2",',
    '    "pyyaml==6.0.2",',
    '    "pillow==10.0.0",',  # drifted
    "]"
  ))
  expect_message(audit_pins(proj), "pillow==10.0.0.*pillow==11.1.0")
})

test_that("multiple drifted deps: one message each", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    "reportifyr = [",
    '    "python-docx==1.0.0",',  # drifted
    '    "pyyaml==6.0.2",',
    '    "pillow==10.0.0",',  # drifted
    "]"
  ))
  msgs <- testthat::capture_messages(audit_pins(proj))
  expect_equal(length(msgs), 2L)
  expect_true(any(grepl("python-docx", msgs)))
  expect_true(any(grepl("pillow", msgs)))
})

test_that("group not in bundled spec: skipped silently", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    'mygroup = ["requests==2.31.0"]'
  ))
  expect_no_message(audit_pins(proj))
})

test_that("missing dep (in bundled but not in project): skipped here", {
  proj <- tempfile()
  dir.create(proj)
  # reportifyr group missing pyyaml — that's a structural concern,
  # write_group_to_pyproject() handles it. audit_pins is silent.
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    "reportifyr = [",
    '    "python-docx==1.1.2",',
    '    "pillow==11.1.0",',
    "]"
  ))
  expect_no_message(audit_pins(proj))
})

test_that("groups arg scopes audit: drifted sibling group is silenced", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    "reportifyr = [",
    '    "python-docx==1.1.2",',
    '    "pyyaml==6.0.2",',
    '    "pillow==10.0.0",',
    "]",
    "presentifyr = [",
    '    "python-pptx==0.6.0",',
    '    "pillow==10.0.0",',
    "]"
  ))
  msgs <- testthat::capture_messages(
    audit_pins(proj, groups = "presentifyr")
  )
  # Only presentifyr drift surfaces; reportifyr's pillow drift is silent.
  expect_true(any(grepl("'presentifyr'", msgs)))
  expect_false(any(grepl("'reportifyr'", msgs)))
})

test_that("groups arg with no matching group: silent", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[dependency-groups]",
    "reportifyr = [",
    '    "pillow==10.0.0",',
    "]"
  ))
  expect_no_message(audit_pins(proj, groups = "nonexistent-group"))
})

test_that("drift in one group does not silence other groups", {
  proj <- tempfile()
  dir.create(proj)
  write_toml(proj, c(
    "[project]",
    'name = "test"',
    "",
    "[dependency-groups]",
    "reportifyr = [",
    '    "python-docx==1.1.2",',
    '    "pyyaml==6.0.2",',
    '    "pillow==10.0.0",',
    "]",
    "presentifyr = [",
    '    "python-pptx==0.6.0",',
    '    "pillow==10.0.0",',
    "]"
  ))
  msgs <- testthat::capture_messages(audit_pins(proj))
  # Two groups, two drifted deps each (pillow + python-pptx in
  # presentifyr; pillow in reportifyr).
  expect_true(any(grepl("'reportifyr'.*pillow", msgs)))
  expect_true(any(grepl("'presentifyr'.*pillow", msgs)))
  expect_true(any(grepl("'presentifyr'.*python-pptx", msgs)))
})
