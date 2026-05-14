test_that("continue() auto-confirms in non-interactive sessions", {
  mockery::stub(continue, "interactive", function() FALSE)

  expect_equal(continue(), "Y")
})
