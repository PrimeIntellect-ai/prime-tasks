Add __len__ to program objects
Add __len__ method to program objects so that users can do `len(program)`.

Note there is a bit of difficulty here in that the program has to be synthesized [HIDDEN], [HIDDEN]

### Additional contract requirements

- `len(program)` must return the number of instruction lines in the fully synthesized program.
