Handle pre-releases correctly
Implement rule from PEP-440:
https://pip.pypa.io/en/stable/reference/pip_install/#install-pre

Possibly add ``--pre`` flag just like in ``pip``:
https://www.python.org/dev/peps/pep-0440/#handling-of-pre-releases

### Additional contract requirements

- Add a `--pre` command-line option (with a `--no-pre` counterpart, off by default) that controls whether pre-release and development versions are considered when resolving package versions. The parsed options expose this as `:pre` with a default of `false`.
- `pip-license-checker.version/filter-versions` accepts an optional `:pre` keyword argument (default `true`). When `:pre` is `false`, pre-release and development versions are excluded from the result whenever at least one stable version satisfies the specifiers; if no stable version satisfies the specifiers, the matching pre-release and development versions are returned.
- `pip-license-checker.version/version-stable?` takes a parsed version and returns `true` exactly when the version has neither a `:pre` nor a `:dev` component.
- `pip-license-checker.version/get-version` accepts an optional `:pre` keyword argument (default `true`) that controls whether pre-release and development versions are considered, and returns the textual representation of the highest version satisfying the specifiers under that policy, or `nil` when no version matches.
- `pip-license-checker.pypi/get-requirement-version` accepts an optional `:pre` keyword argument that controls whether pre-release and development versions are considered when selecting the version, and returns the generic package response when no suitable version exists.
- `pip-license-checker.pypi/requirement->license` accepts an optional `:pre` keyword argument that controls whether pre-release and development versions are considered when selecting the version.
