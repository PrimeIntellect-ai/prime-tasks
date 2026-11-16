Dependencies are upgraded to new major versions during release
## Affected Packages

Probably:
* assemble-release-plan
* apply-release-plan

## Problem

Let's say we have a repo with three projects: foo@2.0.0, bar@2.0.0, qar@2.0.0

foo has qar@2.0.0 in the dependencies. Which is the same as in the monorepo.

bar has an older version of qar in dependencies: 1.0.0.

Now if I release a new version of qar (v2.0.1), I only want to get it bumped inside foo. I want bar to keep using qar@1.0.0

However, seems like in some cases qar is bumped in bar as well. The reason is probably that assemble-release-plan is checking the semver ranges when finding dependents but apply-release-plan is not checking the semver ranges.

## Proposed solution

Maybe we should pass more state to apply-release-plan, to prevent it from making breaking/unwanted bumps

### Additional contract requirements

- The changesets configuration accepts an optional boolean option named `bumpVersionsWithWorkspaceProtocolOnly`. When it is not set, it defaults to `false`.
- When `bumpVersionsWithWorkspaceProtocolOnly` is `true`, a dependency is only considered for automatic version bumping when its version range is prefixed with the `workspace:` protocol. Dependencies expressed with any other range are left unchanged.
- The option is read from the changesets configuration and propagated through configuration parsing, so that a configuration file that sets it to `true` yields a parsed configuration whose `bumpVersionsWithWorkspaceProtocolOnly` value is `true`.
