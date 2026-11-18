## Verifies that the `groups` arg flows from initialize_python() through
## to the shell/PowerShell invocation as positional/`-Groups` args, and
## that NULL triggers the all-groups branch. Tests work against a
## pre-seeded pyproject.toml so initialize_python() skips the seed step
## and goes straight to the platform setup script.
##
## Tests use mockery::stub at the test_that() call site (not in a helper)
## because mockery scopes stubs to the function frame they're set in.

stub_processx_capture <- function(captured) {
  function(command, args, ...) {
    if (is.null(captured$first_args)) {
      captured$first_args <- args
    }
    list(stdout = "", stderr = "", status = 0)
  }
}

# Drop a minimal pyproject.toml in `dir` so initialize_python skips
# seeding.
seed_test_toml <- function(dir) {
  writeLines(
    c(
      "[project]",
      'name = "test"',
      'requires-python = ">=3.12"',
      "",
      "[dependency-groups]",
      'reportifyr = ["pillow==11.1.0"]'
    ),
    file.path(dir, "pyproject.toml")
  )
}

test_that("initialize_python(groups = NULL) sends no group args", {
  skip_on_os("windows")
  proj <- tempfile()
  dir.create(proj)
  seed_test_toml(proj)
  withr::local_options(list(venv_dir = proj))

  captured <- new.env()
  mockery::stub(initialize_python, "continue", function() "Y")
  mockery::stub(initialize_python, "get_uv_path", function(...) "/fake/uv")
  mockery::stub(initialize_python, "system.file", function(...) "/fake/cmd")
  mockery::stub(
    initialize_python, "processx::run", stub_processx_capture(captured)
  )

  initialize_python(continue = "Y", uv_version = "0.7.8", groups = NULL)

  expect_equal(length(captured$first_args), 3L)
})

test_that("initialize_python treats an empty prompt response as Y", {
  skip_on_os("windows")
  proj <- tempfile()
  dir.create(proj)
  seed_test_toml(proj)
  withr::local_options(list(venv_dir = proj))

  captured <- new.env()
  # readline() returns "" when the user presses Enter, which accepts the
  # capitalised default in [Y/n]
  mockery::stub(initialize_python, "continue", function() "")
  mockery::stub(initialize_python, "get_uv_path", function(...) "/fake/uv")
  mockery::stub(initialize_python, "system.file", function(...) "/fake/cmd")
  mockery::stub(
    initialize_python, "processx::run", stub_processx_capture(captured)
  )

  expect_no_error(initialize_python(uv_version = "0.7.8", groups = NULL))
  expect_equal(length(captured$first_args), 3L)
})

test_that("initialize_python still rejects an invalid prompt response", {
  skip_on_os("windows")
  proj <- tempfile()
  dir.create(proj)
  seed_test_toml(proj)
  withr::local_options(list(venv_dir = proj))

  mockery::stub(initialize_python, "continue", function() "maybe")

  expect_error(
    initialize_python(uv_version = "0.7.8", groups = NULL),
    "Must enter Y or n"
  )
})

test_that("initialize_python(groups = 'reportifyr') appends group name", {
  skip_on_os("windows")
  proj <- tempfile()
  dir.create(proj)
  seed_test_toml(proj)
  withr::local_options(list(venv_dir = proj))

  captured <- new.env()
  mockery::stub(initialize_python, "continue", function() "Y")
  mockery::stub(initialize_python, "get_uv_path", function(...) "/fake/uv")
  mockery::stub(initialize_python, "system.file", function(...) "/fake/cmd")
  mockery::stub(
    initialize_python, "processx::run", stub_processx_capture(captured)
  )

  initialize_python(
    continue = "Y", uv_version = "0.7.8", groups = "reportifyr"
  )

  expect_equal(length(captured$first_args), 4L)
  expect_equal(captured$first_args[[4]], "reportifyr")
})

test_that("initialize_python(groups = c('a', 'b')) appends both groups", {
  skip_on_os("windows")
  proj <- tempfile()
  dir.create(proj)
  seed_test_toml(proj)
  withr::local_options(list(venv_dir = proj))

  captured <- new.env()
  mockery::stub(initialize_python, "continue", function() "Y")
  mockery::stub(initialize_python, "get_uv_path", function(...) "/fake/uv")
  mockery::stub(initialize_python, "system.file", function(...) "/fake/cmd")
  mockery::stub(
    initialize_python, "processx::run", stub_processx_capture(captured)
  )

  initialize_python(
    continue = "Y", uv_version = "0.7.8", groups = c("a", "b")
  )

  expect_equal(length(captured$first_args), 5L)
  expect_equal(captured$first_args[[4]], "a")
  expect_equal(captured$first_args[[5]], "b")
})

test_that("initialize_python passes pyproject_dir as the toml_dir arg", {
  skip_on_os("windows")
  proj <- tempfile()
  dir.create(proj)
  seed_test_toml(proj)
  withr::local_options(list(venv_dir = tempfile()))  # different from proj

  captured <- new.env()
  mockery::stub(initialize_python, "continue", function() "Y")
  mockery::stub(initialize_python, "get_uv_path", function(...) "/fake/uv")
  mockery::stub(initialize_python, "system.file", function(...) "/fake/cmd")
  mockery::stub(
    initialize_python, "processx::run", stub_processx_capture(captured)
  )

  initialize_python(
    continue = "Y", uv_version = "0.7.8",
    pyproject_dir = proj, groups = "reportifyr"
  )

  # args: venv_dir, pyproject_dir, uv_version, group
  expect_equal(captured$first_args[[2]], normalizePath(proj, winslash = "/"))
  expect_equal(captured$first_args[[4]], "reportifyr")
})

test_that("initialize_python hands the setup script absolute paths", {
  skip_on_os("windows")
  parent <- withr::local_tempdir()
  proj <- file.path(parent, "proj")
  dir.create(proj)
  seed_test_toml(proj)
  withr::local_dir(parent)
  withr::local_options(list(venv_dir = NULL))

  captured <- new.env()
  mockery::stub(initialize_python, "get_uv_path", function(...) "/fake/uv")
  mockery::stub(initialize_python, "system.file", function(...) "/fake/cmd")
  mockery::stub(
    initialize_python, "processx::run", stub_processx_capture(captured)
  )

  expect_message(
    initialize_python(
      continue = "Y", uv_version = "0.7.8", venv_dir = "proj/"
    ),
    paste0("Preparing Python environment in ", normalizePath(proj)),
    fixed = TRUE
  )

  expected <- normalizePath(proj, winslash = "/")
  expect_equal(captured$first_args[[1]], expected)
  expect_equal(captured$first_args[[2]], expected)
  # The cached root must not depend on the working directory.
  expect_equal(getOption("venv_dir"), expected)
})

test_that("initialize_python expands ~ before calling the setup script", {
  skip_on_os("windows")
  home <- withr::local_tempdir()
  dir.create(file.path(home, "proj"))
  seed_test_toml(file.path(home, "proj"))
  withr::local_envvar(HOME = home)
  withr::local_options(list(venv_dir = NULL))

  captured <- new.env()
  mockery::stub(initialize_python, "get_uv_path", function(...) "/fake/uv")
  mockery::stub(initialize_python, "system.file", function(...) "/fake/cmd")
  mockery::stub(
    initialize_python, "processx::run", stub_processx_capture(captured)
  )

  suppressMessages(initialize_python(
    continue = "Y", uv_version = "0.7.8", venv_dir = "~/proj"
  ))

  expected <- normalizePath(file.path(home, "proj"), winslash = "/")
  expect_equal(captured$first_args[[1]], expected)
  expect_equal(captured$first_args[[2]], expected)
})

test_that("abs_path handles nonexistent, trailing-slash and invalid input", {
  skip_on_os("windows")
  parent <- withr::local_tempdir()
  withr::local_dir(parent)
  root <- normalizePath(parent, winslash = "/")

  expect_equal(abs_path("not/there/"), file.path(root, "not/there"))
  expect_equal(abs_path("/not/there//"), "/not/there")
  expect_equal(abs_path("/not//there"), "/not/there")
  expect_equal(abs_path("/"), "/")
  expect_equal(abs_path("."), root)
  expect_error(abs_path(""), "single non-empty path")
  expect_error(abs_path(NA_character_), "single non-empty path")
  expect_error(abs_path(c("a", "b"), "venv_dir"), "`venv_dir` must be")
})

test_that("initialize_python seeds pyproject.toml when missing", {
  skip_on_os("windows")
  proj <- tempfile()
  dir.create(proj)
  withr::local_options(list(venv_dir = proj))

  captured <- new.env()
  mockery::stub(initialize_python, "continue", function() "Y")
  mockery::stub(initialize_python, "get_uv_path", function(...) "/fake/uv")
  mockery::stub(initialize_python, "system.file", function(...) "/fake/cmd")
  mockery::stub(
    initialize_python, "processx::run", stub_processx_capture(captured)
  )

  expect_false(file.exists(file.path(proj, "pyproject.toml")))
  initialize_python(
    continue = "Y", uv_version = "0.7.8", groups = "reportifyr"
  )
  expect_true(file.exists(file.path(proj, "pyproject.toml")))

  # Seed contains the requested group only.
  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("\\[dependency-groups\\]", lines)))
  expect_true(any(grepl("^reportifyr = \\[", lines)))
  expect_false(any(grepl("^presentifyr = \\[", lines)))
})

test_that("initialize_python errors when pyproject_dir does not exist", {
  skip_on_os("windows")
  nonexistent <- file.path(tempfile(), "deeper", "still-not-real")

  mockery::stub(initialize_python, "continue", function() "Y")
  mockery::stub(initialize_python, "get_uv_path", function(...) "/fake/uv")

  expect_error(
    initialize_python(
      continue = "Y", uv_version = "0.7.8",
      pyproject_dir = nonexistent, venv_dir = tempdir()
    ),
    "pyproject_dir does not exist"
  )
  expect_false(dir.exists(nonexistent))
})

test_that("initialize_python seeds all bundled groups when groups = NULL", {
  skip_on_os("windows")
  proj <- tempfile()
  dir.create(proj)
  withr::local_options(list(venv_dir = proj))

  captured <- new.env()
  mockery::stub(initialize_python, "continue", function() "Y")
  mockery::stub(initialize_python, "get_uv_path", function(...) "/fake/uv")
  mockery::stub(initialize_python, "system.file", function(...) "/fake/cmd")
  mockery::stub(
    initialize_python, "processx::run", stub_processx_capture(captured)
  )

  initialize_python(continue = "Y", uv_version = "0.7.8", groups = NULL)

  lines <- readLines(file.path(proj, "pyproject.toml"))
  expect_true(any(grepl("^reportifyr = \\[", lines)))
  expect_true(any(grepl("^presentifyr = \\[", lines)))
})
