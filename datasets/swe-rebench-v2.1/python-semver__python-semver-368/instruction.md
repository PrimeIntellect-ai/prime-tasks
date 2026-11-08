Feature request: concise "compatibility" matching
I'd really like a concise expression for "is version x compatible with version y?"

Specifically, suppose I write code against one version of an API, and the API exposes a semver-compliant version. Is `v_caller` compatible with `v_api`?

The most concise expression I can come up with is something like `[HIDDEN]`, but I really wish this was simpler and more readable. Maybe `v_caller.compatible(v_api)`; or maybe `v_caller.can_call(v_api)` better illustrates which operand is which.

I know this would be covered by #241, but its scope is quite broad. I wanted to specifically call out this feature.

### Additional contract requirements

- Expose the operation as `Version.is_compatible(self, other: Version) -> bool`, with the caller version as `self` and the API version as `other`.
- Identical versions are compatible. For nonzero major versions, compatibility requires the same major, an API minor version at least as large as the caller's, and equal prerelease identifiers; patch versions do not affect this check. Major-zero versions are compatible only when identical.
