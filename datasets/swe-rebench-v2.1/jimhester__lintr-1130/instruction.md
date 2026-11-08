Test warnings reappeared
The tests currently produce a load of warnings:

 - [ ] Warning (test-cache.R:91:3): load_cache returns an empty environment if reading cache file fails
truncating string with embedded nuls

 - [ ] Warning (test-cache.R:91:3): load_cache returns an empty environment if reading cache file fails
file '417d412957880ef5bb7f5c9782b04500e1bf3c5f' has magic number 'X'
  Use of save versions prior to 2 is deprecated

 - [ ] Warning (test-cache.R:435:3): cache = TRUE workflow works
'relative_path' is no longer available as a positional argument; please supply 'relative_path' as a named argument instead. This warning will be upgraded to an error in the next release.

 - [ ] Warning (test-cache.R:436:3): cache = TRUE workflow works
'relative_path' is no longer available as a positional argument; please supply 'relative_path' as a named argument instead. This warning will be upgraded to an error in the next release.

 - [ ] Warning (test-comments.R:8:1): (code run outside of `test_that()`)
`setup()` was deprecated in the 3rd edition.
ℹ Please use test fixtures instead see vignette('test-fixtures') for details

 - [ ] Warning (test-comments.R:12:1): (code run outside of `test_that()`)
`teardown()` was deprecated in the 3rd edition.
ℹ Please use test fixtures instead see vignette('test-fixtures') for details

### Additional contract requirements

The test suite should run without emitting the testthat deprecation warnings for `setup()` and `teardown()`.
