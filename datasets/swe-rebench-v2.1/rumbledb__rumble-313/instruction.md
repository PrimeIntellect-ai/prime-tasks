tokenize() issue with " "
tokenize() sometimes throws a NullPointerException when [HIDDEN] is looked up.

### Additional contract requirements

- `tokenize(" ")` must return the empty sequence instead of raising an error.
