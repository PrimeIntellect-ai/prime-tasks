Py2 vs. Py3 incompatibility: TypeError
# Situation

I'm confused by the statement in the Readme that seems to say 2.10.0 _does_ still support Python 2.7. That's not what I'm seeing. I have a project that uses this package and runs in Py2, and as soon as it started using the 2.10 release, I started getting errors like this which look to me like what you'd get from a Py2 vs. Py3 incompatibility:

    TypeError("Expected str or VersionInfo instance, but got <type 'unicode'>"

When I pin the dependency to `<2.10`, the error goes away.

_Originally posted by @eli-darkly in https://github.com/python-semver/python-semver/issues/161#issuecomment-654455352_

### Additional contract requirements

The library must accept both text and binary strings wherever a version string is expected (for example in `semver.compare` and `semver.VersionInfo.parse`), on both Python 2 and Python 3.

The `semver` module must expose the following public names:

- `semver.ensure_str(s, encoding="utf-8", errors="strict")`: returns a native `str`. On Python 3, a `bytes` argument is decoded to `str` using `encoding` and `errors`, and a `str` argument is returned unchanged. On Python 2, a `unicode` argument is encoded to `str` using `encoding` and `errors`, and a `str` argument is returned unchanged. It raises `TypeError` when `s` is neither a supported text nor binary type.
- `semver.PY2`: `True` on Python 2 and `False` on Python 3.
- `semver.u(s)`: returns a text string for use with the library.
- `semver.b(s)`: returns a binary string for use with the library.
- `semver.text_type`: the text string type of the running Python version.
- `semver.binary_type`: the binary string type of the running Python version.
