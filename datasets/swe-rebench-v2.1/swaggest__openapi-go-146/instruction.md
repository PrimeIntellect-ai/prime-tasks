writeOnly tags aren't handled by spec reflection
## Description
`readOnly` is supported as a tag on structs in reflection. I'd expect that `writeOnly` would also be supported, but it doesn't appear to be (see reproduction).

## Reproduction
https://go.dev/play/p/gQ5lvj7oTeL

## Expected
I expected that the `writeOnly` tag would be present on the field on which the associated tag was added, in the same manner as `readOnly`.

### Additional contract requirements

- Also, a struct field tagged `deprecated:"true"` must have `"deprecated": true` on that field in reflected output.
