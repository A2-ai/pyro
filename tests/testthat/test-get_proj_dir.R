test_that("get_proj_dir() returns option when set", {
  proj <- withr::local_tempdir()
  withr::local_options(list(venv_dir = proj))
  expect_equal(get_proj_dir(), normalizePath(proj, winslash = "/"))
})

test_that("get_proj_dir() falls back to here::here() when option unset", {
  withr::local_options(list(venv_dir = NULL))
  expect_equal(get_proj_dir(), here::here())
})

test_that("get_proj_dir() makes a relative or tilde option absolute", {
  proj <- withr::local_tempdir()
  withr::local_dir(proj)

  withr::local_options(list(venv_dir = "."))
  expect_equal(get_proj_dir(), normalizePath(proj, winslash = "/"))
  # The option is pinned, so a later setwd() does not move the root.
  expect_equal(getOption("venv_dir"), normalizePath(proj, winslash = "/"))
  withr::local_dir(tempdir())
  expect_equal(get_proj_dir(), normalizePath(proj, winslash = "/"))

  withr::local_options(list(venv_dir = "~/some-project"))
  expect_equal(
    get_proj_dir(),
    abs_path(file.path(path.expand("~"), "some-project"))
  )
  expect_false(grepl("~", get_proj_dir(), fixed = TRUE))
})
