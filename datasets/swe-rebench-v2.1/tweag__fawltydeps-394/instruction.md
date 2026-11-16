FawltyDeps fails running on itself
**Describe the bug**
When I install from scratch a developer's environment and run `fawltydeps` in it I get following message:
```
(fawltydeps-py3.11) ➜  FawltyDeps git:(main) fawltydeps

These imports appear to be undeclared dependencies:
- 'pkg_resources'

These dependencies appear to be unused (i.e. not imported):
- 'setuptools'
- 'types-setuptools'

For a more verbose report re-run with the `--detailed` option.
```

**To Reproduce**
Run fawltydeps from `poetry shell`.

**Expected behavior**
FawltyDeps does not report any missing or unused dependencies

**Environment**
 - OS name + version: I tested on Ubuntu and Windows.
 - Version of the code:
 ```
(fawltydeps-py3.11) ➜  FawltyDeps git:(main) fawltydeps --version
FawltyDeps v0.13.2
(fawltydeps-py3.11) ➜  FawltyDeps git:(main) which fawltydeps
/home/mknorps/.cache/pypoetry/virtualenvs/fawltydeps-RB6LwJVc-py3.11/bin/fawltydeps
```

### Additional contract requirements

- Add a public class `SysPathPackageResolver` in module `fawltydeps.packages`. It resolves packages installed in the current Python environment (the interpreter's `sys.path`). It provides a `packages` property returning a mapping from normalized package names to `Package` objects, and a `lookup_packages(package_names)` method returning only the requested entries that are present in that mapping.
- `setup_resolvers` in module `fawltydeps.packages` accepts a boolean keyword argument `use_current_env` (default `False`). When it is `True`, the resolver sequence includes a `SysPathPackageResolver` after any `LocalPackageResolver`.
