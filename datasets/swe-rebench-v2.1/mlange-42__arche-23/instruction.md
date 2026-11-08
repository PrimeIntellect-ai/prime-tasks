Zero Entity singleton
`Entity` should have a zero value singleton, and possibly a method `Zero() bool`.

This is useforfor storing entity IDs with the possibility for zero/nil/unset.

### Additional contract requirements

The zero-valued `Entity` is reserved to represent an unset or nil entity and must not be considered live. Entities allocated by a world must not use the zero value.
