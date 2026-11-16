Deprecate Valid() and add Wellformed() to replace it
RFC 8949 distinctly defines what is "Valid" and what is "Well-formed".

Although the old docs for Valid() correctly said it checks for well-formedness, Valid() is not an appropriate function name because it can lead to confusion.

### Proposed Solution

- Add Wellformed() as a replacement for Valid().
- For now, deprecate Valid() and [HIDDEN].  This makes Valid() behave the same in v2.5.0 as prior releases.

Wellformed() checks whether data is a well-formed encoded CBOR data item and that it complies with additional restrictions such as MaxNestedLevels, MaxArrayElements, MaxMapPairs, etc.  If there are any remaining bytes after the encoded CBOR data item, then ExtraneousDataError is returned.

:warning: Projects should begin replacing calls to Valid() with calls to WellFormed().

### Additional contract requirements

- Provide both the package-level `Wellformed` function and a corresponding `DecMode.Wellformed` method. The method must validate using that mode's configured options.
- Keep `Valid` available as a deprecated compatibility API, preserving the validation behavior previously provided by `Valid`.
- Both public `Wellformed` entry points must reject malformed CBOR data items. A mode-specific method must also enforce configured restrictions, including nesting, array-element, and map-pair limits.
