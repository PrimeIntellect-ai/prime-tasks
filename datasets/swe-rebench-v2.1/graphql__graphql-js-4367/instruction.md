Input object coercion should reject arrays directly
If an array is fed into input object coercion it should be rejected directly, rather than passing the object check and then failing on the keys checks.

See this repro:

https://gist.github.com/benjie/58ba75340a85b0da4b403973bea2c5fb

Seems like adding a [HIDDEN] check should cover it?

### Additional contract requirements

- When rejecting an array, report `Expected type "<TypeName>" to be an object.`, using the input object's GraphQL type name.
- Reject an array at its current input path and report the array itself as the rejected value, rather than reporting errors for its elements or keys.
