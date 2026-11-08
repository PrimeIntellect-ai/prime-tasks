fix: license check should not treat lack of dependencies as an error
### Description

If the license checker is run on a package with no direct dependencies it exits with a non-zero exit code (treated as an error). This is not correct behavior imo because if a package has no direct dependencies it should still be considered as passing the license check.

### Steps To Reproduce

1. Create a package with a single internal path dependency
2. Run the license check command
3. Observe the error: `No hosted dependencies found in ./path/to/package of type: direct-main.`

### Expected Behavior

I'd expect the case with no dependencies that match the type to be considered passing since no dependencies means the package isn't violating any licensing rules.

### Additional Context

_No response_
