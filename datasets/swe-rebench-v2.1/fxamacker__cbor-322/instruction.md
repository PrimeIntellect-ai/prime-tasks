feature: Add feature to query next element size from stream decoder
**Is your feature request related to a problem? Please describe.**

In Cadence we would like to know the length of the next element that is to be decoded in a stream decoder.
For example, when `StreamDecoder.NextType` returns `TextStringType`, we call `DecodeString` to decode the string. Now we would like to know the length of the string before the string is decoded.

Currently, there is no such information available.

**Describe the solution you'd like**

Allow a user of the stream decoder to query the length of the next element that is to be decoded in a stream decoder, before the element itself is actually decoded.

This could be exposed similarly to the function returning the next element's type, `NextType`, as e.g. `NextSize`.
It could also be useful to add a function that returns both values in one function call, e.g. `NextTypeAndSize`.

**Describe alternatives you've considered**

*None*

**Additional context**

*None*

### Additional contract requirements

`StreamDecoder.NextSize` reports the size of the next definite-length byte string or text string in payload bytes, an array in number of elements, or a map in number of key/value pairs. It reports an error for indefinite-length values and types for which a size is not supported. Querying the size must not consume the next value, which remains available for subsequent decoding. The particular error type and the size result returned when an error occurs are unspecified.
