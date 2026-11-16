Remove string length limitation
### Describe the feature
Currently the type of a local string is printed as `character(len=280)`, it should be possible to replace this with [HIDDEN]

### Additional contract requirements

- Fortran local strings must support values longer than the current fixed-length limit without truncation. Operations that obtain a string's length must report the actual number of characters in the value.
