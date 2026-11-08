Remove [HIDDEN] functionality
This isn't needed since I've decided to keep single-doc Get() separate from OpenRevs(), and removing it will allow for more consistent handling of iterators.

### Additional contract requirements

- Accessing a result before explicitly advancing the iterator with `Next()` must not advance it implicitly; the access must return an error indicating that `Next()` has not been called.
