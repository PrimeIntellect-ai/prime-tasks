Problems with python finding itself
Opening for @deitch  (feel free to retitle and/or correct the below!)

When debugging failing E2E tests in Melange (e.g. https://github.com/chainguard-dev/melange/actions/runs/4743961439/jobs/8424331419?pr=395) we noticed two issues:

1. the apk implementation doesn't have support for using tilde (`~`) to specify a version for a dependency
2. the apk implementation doesn't have support a package depending directly on itself (i.e. not on a provides, but the package itself) — e.g. `python3` depending on `python3~3.11`

### Additional contract requirements

- A dependency version written with a tilde (`~`) matches any version that shares the given numeric prefix: `~1.5` matches `1.5.0` and `1.5.1`, but not `1.0.0` or `2.0.0`.
- A package that lists itself as a dependency is satisfied by the package itself when the package's own version matches the requested version constraint, and the package is not reported as a dependency of itself.
