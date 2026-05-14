test_that("get_proj_dir() returns option when set", {
  withr::local_options(list(venv_dir = "/some/path"))
  expect_equal(get_proj_dir(), "/some/path")
})

test_that("get_proj_dir() falls back to here::here() when option unset", {
  withr::local_options(list(venv_dir = NULL))
  expect_equal(get_proj_dir(), here::here())
})
