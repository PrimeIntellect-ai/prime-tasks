Please, correct the typo: endianess -> endianness
The correct spelling of the word "endianess" is "endianness". A typo exists in the documentation as well as in the method names.

### Additional contract requirements

- The `Parser` class in `lib/binary_parser.ts` exposes a method `endianness(endianness: "little" | "big")`.
- `endianness` returns the same `Parser` instance so that calls can be chained.
- The byte order argument is accepted case-insensitively.
- Calling `endianness` configures the byte order used when parsing subsequent primitive fields.
- Any value other than `"little"` or `"big"` throws an `Error`.
- The repository's README documentation must use the correct spelling `endianness` and must not contain the misspelling `endianess`.
