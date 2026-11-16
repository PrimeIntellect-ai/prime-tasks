Provide a `safer_getattr` variant with `getattr` compatible signature
We started to advertise `safer_getattr` as a safe `getattr` implementation candidate in a typical `RestrictedPython` environment **BUT** `safer_getattr` has a different signature and semantics than `getattr`: `safer_getattr` has by default the parameter `default=None`  while `getattr` lacks this parameter by default and then raise `AttributeError` (rather than returning the default value).

I propose to provide (additionally) a variant of `safer_getattr` (say `safer_getattr_exc`) mirroring the signature and behavior of `getattr`. Application can then decide which variant they want to use for their `_getattr_`.

### Additional contract requirements

Expose the additional variant as `RestrictedPython.Guards.safer_getattr_raise` so applications can choose it for `_getattr_`. It must retain the safety restrictions of `safer_getattr`, including rejecting restricted attribute names and denying access to the unsafe `str.format` and `str.format_map` methods.
