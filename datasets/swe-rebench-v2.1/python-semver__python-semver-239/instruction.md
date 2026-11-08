Deprecate missing module-level functions (like semver.compare, semver.match, ...)
# Situation

We deprecated most of our module-level functions, but it seems, I forgot `semver.match`.

# Proposal

I assume, this function should also be added to the list of deprecated function. It also should be moved to the `semver.VersionInfo` class.

@python-semver/reviewers Any objections?

---

There are some other module-level functions:

* `semver.compare`
* `semver.max_ver`
* `semver.min_ver`

@gsakkis: What should we do with these? Deprecate them too and move them to the `semver.VersionInfo` class?

### Additional contract requirements

- The matching operation is available as a public method `match(match_expr)` on `semver.VersionInfo`, returning `True` or `False`.
