PrefixList raises ValueError instead of TraitError while validating static default
Static default value is currently validated in `PrefixList` in order to apply the needed transform (similar use case to PrefixMap, see #1130).
However the validation error is a `ValueError`. It should be `TraitError` as this is a validation error.

https://github.com/enthought/traits/blob/b983edfd612b5de435b239b0871a13a2b7cc90da/traits/trait_types.py#L2608-L2612
