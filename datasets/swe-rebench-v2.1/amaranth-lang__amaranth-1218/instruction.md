Make the use of `Elaboratable` for elaboratable objects required
It's always required a warning. Technically it's not a deprecation warning, but it might as well be; none of our other protocol classes (`ValueCastable` for example) are optional, `Elaboratable` shouldn't be either.

### Additional contract requirements

- `Fragment.get(obj, platform=None)` in module `amaranth.hdl._ir` returns a `Fragment` representing the elaborated hardware description. It accepts an existing `Fragment` or an instance of a class that inherits from `Elaboratable`. Any other object, including one that merely defines an `elaborate` method without inheriting from `Elaboratable`, is rejected with a `TypeError` whose message is `Object {obj!r} is not an 'Elaboratable' nor 'Fragment'`.
- If an `Elaboratable` object's `elaborate()` method returns `None`, a `UserWarning` with the message `.elaborate() returned None; missing return statement?` is emitted.


- After emitting that warning, raise a `TypeError` with the message `Object None is not an 'Elaboratable' nor 'Fragment'`.
- If an `Elaboratable` object's `elaborate()` method returns the object itself, raise a `RecursionError` with the message `Object {obj!r} elaborates to itself`.
