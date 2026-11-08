bump_build() and bump_prerelease() have the wrong rtype
These two methods return `VersionInfo` objects, the `rtype` in the docstring says that they return a `str`.
