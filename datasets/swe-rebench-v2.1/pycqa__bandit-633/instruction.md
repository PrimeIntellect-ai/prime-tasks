One-liner in bandit config to skip B101 assert_used in files matching a filter
Currently you can exclude a directory and you can skip certain tests across all scanned files. It would be very handy to be able to exclude test_* pytest files from the B101 assert test with a simple one liner in the .bandit config file.

This is a feature request for something like:

In .bandit
```
[bandit]
pytest_filter: test_* #excludes B101 in files matching test_*
```

Excluding all B101 is not a good solution, because I want to know about B101 in non-test modules.

Also, I'd like to be able to exclude on file filter like test_* rather than directory test/ because that filter works better across projects I have seen where test directory might not be named consistently, but all the pytests are generally named a special way e.g. test_*

This will allow a more general (across projects) config file to be set up.

### Additional contract requirements

The file-based B101 filtering is configured in the bandit config file (for
example `.bandit`) using the test name `assert_used` and a `skips` list of glob
patterns matched against the file name:

```yaml
assert_used:
  skips: ['test.py$', '^test']
```

A file whose name matches any pattern in `skips` produces no B101 finding;
files that do not match any pattern are still checked.
