LogicValue radixStrings should use underscore as separator, similar to Dart 3.6
### Motivation

Dart has moved to allowing underscores in digit strings to make them more readable.
LogicValue radixStrings were using spaces as separators, not a great choice.
It woud be nice to match Dart with underscores but also allow for other separators upon request.


### Desired solution

Add an optional seperatorChar for ofRadixString and toRadixString, defaulting to '_'.

### Alternatives considered

_No response_

### Additional details

_No response_

### Additional contract requirements

- `LogicValue.ofRadixString` accepts an optional named separator parameter
  `sepChar` of type `String`, defaulting to `'_'`:
  `LogicValue.ofRadixString(String valueString, {String sepChar = '_'})`.
- `LogicValue.toRadixString` accepts an optional named separator parameter
  `sepChar` of type `String`, defaulting to `'_'`:
  `LogicValue.toRadixString({int radix = 2, int chunkSize = 4, String sepChar = '_'})`.
- A separator character must not be one of the legal radix characters
  (`'0123456789aAbBcCdDeEfFqohzZxX`). Supplying such a character as `sepChar`
  is invalid.
- Malformed radix input, an illegal separator, or a value that cannot be
  represented in the specified width raises `LogicValueConstructionException`.
- An unsupported radix or an illegal separator passed to `toRadixString`
  raises `LogicValueConversionException`.
- `LogicValueConversionException` is a public class extending `RohdException`
  with a constructor `LogicValueConversionException(String message)`; its
  `toString()` includes the provided message.
