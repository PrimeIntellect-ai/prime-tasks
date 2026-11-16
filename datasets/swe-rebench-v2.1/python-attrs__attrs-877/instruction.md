matches_re() should accept re.Pattern in addition to str
`attr.validators.matches_re()` does not accept precompiled regular expressions, and instead requires a `str` pattern (and optional flags).

this is not ideal when using existing compiled regular expressions, which already can have flags etc.

it would be a nice addition if the same helper accepts `re.Pattern` (py37+) or `typing.Pattern` for those living in the past.

open questions:

- would `flags=` be allowed if a `re.Pattern` is passed? compiled patterns cannot be ‘reinterpreted’ safely with different flags (e.g. `re.VERBOSE` changes many semantics). that means options are a) reject by raising an exception or b) ignore. my preference is raising.
- in general any reason not to do this?

### Additional contract requirements

- `attr.validators.matches_re(regex, flags=0, func=None)` accepts a pre-compiled regular expression (an `re.Pattern`) as `regex` in addition to a string pattern.
- A compiled pattern is validated with the options already applied to it.
- The public type signature accepts `typing.Pattern` as well as string patterns.
- When `regex` is a pre-compiled pattern and `flags` is non-zero, a `TypeError` is raised whose message contains the exact text `can only be used with a string pattern`.
- `func` selects the underlying matching function and must be one of `None`, `re.match`, `re.search`, or `re.fullmatch` (when available); any other callable raises `ValueError`.
