When pyoptsparse isn't installed, a RuntimeError is raised instead of an ImportError.
### Desired capability or behavior.

When the pyOptSparseDriver detects that pyOptSparse has not been installed, it raises a RuntimeError:

        if pyoptsparse is None:
            # pyoptsparse is not installed
            [HIDDEN]

Should this be an ImportError instead? This would help you group the error with other ImportErrors that are also due to missing packages.

### Associated POEM

This is a small change.

### Additional contract requirements

- When pyOptSparse is unavailable, instantiating `pyOptSparseDriver` must raise `ImportError`, not `RuntimeError`.
