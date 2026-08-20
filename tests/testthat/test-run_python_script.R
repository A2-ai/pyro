test_that("stderr_callback receives whole lines across read boundaries", {
  skip_on_os("windows")

  # processx reads stderr in 2000-byte chunks, so a burst this size is
  # guaranteed to straddle several reads. Each line carries a tag that a
  # partial delivery would sever.
  script <- paste(
    "i=0; while [ $i -lt 200 ]; do",
    "printf '%s\\n' \"line-$i [DEBUG] $(printf 'x%.0s' $(seq 1 40))\" >&2;",
    "i=$((i+1)); done"
  )

  seen <- character()
  pyro::run_python_script(
    uv_path = "sh",
    args = c("-c", script),
    venv_path = tempdir(),
    script_name = "burst",
    stderr_callback = function(line, proc) seen <<- c(seen, line)
  )

  expect_length(seen, 200)
  expect_true(all(grepl("^line-\\d+ \\[DEBUG\\] x{40}$", seen)))
  expect_identical(seen[[1]], paste0("line-0 [DEBUG] ", strrep("x", 40)))
  # No line arrives twice, which is what a mis-flushed buffer would cause.
  expect_length(unique(seen), 200)
})

test_that("a trailing line with no newline is still delivered", {
  skip_on_os("windows")

  seen <- character()
  pyro::run_python_script(
    uv_path = "sh",
    args = c("-c", "printf 'first\\nno-trailing-newline' >&2"),
    venv_path = tempdir(),
    script_name = "partial",
    stderr_callback = function(line, proc) seen <<- c(seen, line)
  )

  expect_identical(seen, c("first", "no-trailing-newline"))
})

test_that("a trailing line is delivered when the script fails", {
  skip_on_os("windows")

  seen <- character()
  expect_error(
    pyro::run_python_script(
      uv_path = "sh",
      args = c("-c", "printf 'context\\nfatal: died here' >&2; exit 1"),
      venv_path = tempdir(),
      script_name = "crasher",
      stderr_callback = function(line, proc) seen <<- c(seen, line)
    ),
    "crasher failed."
  )

  expect_identical(seen, c("context", "fatal: died here"))
})

test_that("flush_partial_line only fires on a withheld line", {
  seen <- character()
  cb <- function(line, proc) seen <<- c(seen, line)

  # Complete output: processx already delivered every line.
  flush_partial_line("a\nb\n", cb)
  expect_length(seen, 0)

  flush_partial_line(NULL, cb)
  flush_partial_line("", cb)
  expect_length(seen, 0)

  flush_partial_line("a\nb", cb)
  expect_identical(seen, "b")

  seen <- character()
  flush_partial_line("a\r\nb", cb)
  expect_identical(seen, "b")
})
