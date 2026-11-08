Make functions to read and write code points public
Currently, there's no way to read a code point from a source containing UTF-8 encoded data or write a single code point to sink encoding it to UTF-8 along the way.

Corresponding functions exist but are hidden: https://github.com/Kotlin/kotlinx-io/pull/136#discussion_r1243305835

It's time to make them public under the following names:
- `Sink.writeCodePointValue(value: Int)`
- `Source.readCodePointValue(): Int`

There is no `Utf8` in the names for consistency with `readString`/`writeString`, but there is a `Value` suffix.
At some point, `CodePoint` type will be added to Kotlin Stdlib, so it'll be nice to preserve `readCointPoint`/`writeCodePoint` names for it. However, such a type most likely will have a `value: Int` property and the names mentioned above are referring to that property.

### Additional contract requirements

- The two functions must be part of the module's public API surface: they must be declared `public` (not `internal`), and the checked-in public API dumps (`core/api/kotlinx-io-core.api` and `core/api/kotlinx-io-core.klib.api`) must list `writeCodePointValue` and `readCodePointValue`. The project's public API check (`apiCheck`) must pass.
