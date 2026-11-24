test_that("pyro_message wraps to the console width and indents", {
  withr::local_options(list(width = 50))
  long <- paste(rep("word", 30), collapse = " ")
  out <- capture.output(pyro_message(long, indent = 2L), type = "message")
  expect_gt(length(out), 1L)
  expect_true(all(nchar(out) <= 50))
  expect_true(all(startsWith(out, "  ")))
})

test_that("pyro_message leaves a short line on one line", {
  withr::local_options(list(width = 80))
  out <- capture.output(pyro_message("Using existing uv 0.13.5"), type = "message")
  expect_equal(out, "Using existing uv 0.13.5")
})
