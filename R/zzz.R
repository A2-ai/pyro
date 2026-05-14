.le <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  .le$logger <- log4r::logger(
    threshold = "DEBUG",
    appenders = list(pyro_console_appender)
  )
}

# Level filtering lives here so that changing `options(pyro.verbose)`
# takes effect on the next log call — no rebuild, no toggle function.
pyro_console_appender <- function(level, ...) {
  threshold <- getOption("pyro.verbose", "WARN")
  order <- c(DEBUG = 1L, INFO = 2L, WARN = 3L, ERROR = 4L, FATAL = 5L)
  if (!(threshold %in% names(order))) threshold <- "WARN"
  if (order[[level]] >= order[[threshold]]) {
    cat(
      format(Sys.time()), " [pyro] [", level, "] ", ..., "\n",
      sep = ""
    )
  }
}
