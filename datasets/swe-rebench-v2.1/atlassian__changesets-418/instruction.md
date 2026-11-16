@changesets/git: getChangedPackagesSinceRef always returns values
## Affected Packages

`@changesets/git`

## Problem

Untested with a monorepo, but calling `getChangedPackagesSinceRef` against a single package with no changes, results in the package being returned.

This is because `getChangedFilesSince(... fullPath: false)` will return `[""]`, rather than the expected `[]`.
`getChangedFilesSince(... fullPath: true)` will join that empty string with the path, and imply that the package has changed.

## Proposed solution

[HIDDEN]
