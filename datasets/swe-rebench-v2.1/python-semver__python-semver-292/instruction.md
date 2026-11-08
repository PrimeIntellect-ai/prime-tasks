semver.VersionInfo allows negative numbers
# Situation

If you pass negative numbers into `semver.VersionInfo` it doesn't raise any errors:

```python
>>> import semver
>>> semver.VersionInfo(-2)
VersionInfo(major=-2, minor=0, patch=0, prerelease=None, build=None)
```

Tested with latest 2.11.0


# Proposal

I guess, this shouldn't happen. We should raise a ValueError exception.
Would integrate that into a 2.12.0 release and into the upcoming 3.0.0-alpha0.

@tlaferriere Thomas, can you conform? Do you agree?
