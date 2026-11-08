Jython should support date passing
Currently the Jython integration knows how to translate strings, ints, longs, and floats.  It should be taught to handle one or more formats that interoperate with Refine's datetime type.

### Additional contract requirements

- Refine's datetime type is `java.time.OffsetDateTime`, and date-time values are always expressed at UTC (`java.time.ZoneOffset.UTC`).
- When the `value` binding holds an `OffsetDateTime`, the Jython script receives it as a Python `datetime.datetime` object.
- When a Jython script returns a Python `datetime.datetime`, the evaluation result is a `java.time.OffsetDateTime` at UTC.
- All other return values keep their existing translations: Python `None` becomes `null`, Python integers become Java `Long` values, Python floats become Java `Double` values, Python strings become Java `String` values, sequences become Java arrays, and other objects are returned unchanged.


- - When `value` is `OffsetDateTime.of(2024, 10, 2, 12, 30, 30, 0, ZoneOffset.UTC)`, `str(value)` in the Jython script returns exactly `2024-10-02 12:30:30`.
