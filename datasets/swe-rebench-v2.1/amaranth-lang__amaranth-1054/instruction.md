`Signal(range(0))` raises `SyntaxWarning`
`Signal(range(0))` raises
```
SyntaxWarning: Reset value 0 equals the non-inclusive end of the signal shape range(0, 0); this is likely an off-by-one error
```
Is this warning intended?
To me this warning is quite confusing, as amaranth implicitly converts `range(0)` (which would be something like a never type) to `unsigned(0)`, and `Signal(unsigned(0))` does not raise the same warning.

Some more discussion can be found in the [IRC logs](https://libera.irclog.whitequark.org/amaranth-lang/2024-01-07#1704643458-1704644743;).

### Additional contract requirements

Constructing `Signal(range(0))` without an explicit reset must not emit the misleading reset fencepost warning. It must remain constructible with the zero-width unsigned shape `unsigned(0)`.
