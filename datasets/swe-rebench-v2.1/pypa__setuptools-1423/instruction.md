Refactor rename find_packages_ns to find_namespace_packages
As @pganssle mentioned in #1420, the export `find_packages_ns` is rather obscure and should be renamed to `find_namespace_packages`. This also goes in line with the new `find_namespace:` directive when using `setup.cfg` that was introduced by the PR #1420 as requested by #1419.

### Additional contract requirements

- Add a public function `find_namespace_packages(where='.', include=None, exclude=None, **kwargs)` in the `setuptools` package, exported on Python 3.
- It returns the list of package names found under `where` that match the `include` patterns and do not match the `exclude` patterns, including PEP 420 implicit namespace packages (directories without an `__init__.py`).
