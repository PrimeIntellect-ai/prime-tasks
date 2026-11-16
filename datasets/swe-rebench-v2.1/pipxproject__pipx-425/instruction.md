Do not store version specifiers in pipx metadata
**How would this feature be useful?**
Currently we record verbatim to `package_or_url` whatever package specification the user submits to `install`.  This has the effect of making a package specification with a version specifier not able to be upgraded in the future.

This change to pipx behavior would allow a specific version to be specified and installed, but still allow it to be upgraded later.

This also would be one step to enabling useful behavior for a future pipx freeze/unfreeze functionality that specifies all versions during an "unfreeze" installation.

**Describe the solution you'd like**
During `pipx install`, install based on whatever requirement specifier the user submits, but strip off any version specifiers before storing `package_or_url` to metadata.

**Describe alternatives you've considered**
There could also be a `--force` flag in `upgrade`, or `upgrade` could simply strip off the version specifier present in the metadata itself (always ignoring the version specifier.)

### Additional contract requirements

- Add a public function `parse_specifier_for_metadata(package_spec: str) -> str` in module `pipx.package_specifier`. It returns a cleaned `package_or_url` value suitable for storing in pipx metadata.
- It accepts any PEP 508-compliant requirement, git URLs, other URLs, and local filesystem paths.
- It strips version specifiers (for example `==`, `>=`, `<=`) and environment markers from the returned value.
- For a PyPI requirement, the package name is normalized to lowercase and runs of `-`, `_` or `.` are replaced with `-`; extras are formatted without spaces between entries, for example `pipx[extra1,extra2]`.
- URL contents are passed through unchanged.
- A local filesystem path is converted to an absolute path.
- If the input cannot be interpreted as a valid specifier, it raises `PipxError` with a message beginning `Unable to parse package spec`.
- During `pipx install`, the package is installed using the requirement specifier the user submitted, while the value stored as `package_or_url` in pipx metadata has version specifiers stripped.
