Add golint package name MixedCaps rule
**Is your feature request related to a problem? Please describe.**
I have been using revive as a "drop-in replacement for golint" but recently noticed revive did not detect an issue I remembered golint used to raise. golint has a rule to check for MixedCaps package names, added in https://github.com/golang/lint/pull/285 and implemented in https://github.com/golang/lint/blob/83fdc39ff7b56453e3793356bcff3070b9b96445/lint.go#L561-L563

**Describe the solution you'd like**
It would be great to have revive's var-naming rule also perform a check for MixedCaps package names.

**Describe alternatives you've considered**
I've considered re-enabling golint and running it alongside revive but that would result in duplicate linter suggestions.

**Additional context**
PR to follow.

### Additional contract requirements

- For a package named `PkgName`, the diagnostic must include `don't use MixedCaps in package name; PkgName should be pkgname`.
