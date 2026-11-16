Unreachable git commits are used for Go module version determination
I have a branch in which I've created a release `rc` tag. In a completely separate branch, from which the `rc` tag is _not_ reachable, I'm getting an "inconsistent versions" error that cites the `rc` tag, saying `Found <rc-tag> which does not match <actual>` (where `<rc-tag>` matches the tag that isn't reachable, and `<actual>` is the expected version).

I can verify that `<actual>` is the most recent reachable tag using `git describe`:

```
> git describe --match 'v*'
v<actual>-2-ga7d9350
```

### Additional contract requirements

The fix applies to both commit resolution and tag resolution, and to every package format
(Cargo, Go, `package.json`, `pyproject.toml`), not only Go modules.

- When determining the current version of a package from Git tags, only tags that are
  reachable from `HEAD` may be considered. A tag that is not reachable from `HEAD` must be
  ignored, even when it is newer than every reachable tag.
- When enumerating the commits that belong to a release, the set of commits must be exactly
  the commits reachable from `HEAD` but not reachable from the previous stable tag (the same
  set as `git rev-list {previous_stable_tag}..HEAD`). Commits that are only reachable from an
  unreachable tag must not be included.
- With `--verbose`, for each tag reference that Knope walks back from, it prints
  `Finding all commits behind {reference}` (for example
  `Finding all commits behind refs/tags/first/v1.2.3`).
