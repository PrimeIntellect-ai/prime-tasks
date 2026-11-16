False positive in expect_length_linter when info= is passed
`testthat::expect_length()` doesn't have `info=` among its formals, so it's not a drop-in replacement for `expect_equal()` when `info=` is used.

Discovered from our own suite:

https://github.com/r-lib/lintr/blob/878dacfc12a39d3e7a130b0c66fc14084ea3d9d6/tests/testthat/test-exclusions.R#L40
