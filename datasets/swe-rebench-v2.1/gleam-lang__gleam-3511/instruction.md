Allow Strings in a BitArray literal without having to specify utf8 encoding
I think it would be a neat little ux improvement to allow strings in a bit array without specifying the encoding, defaulting to utf8.

```gleam
// instead of
<<"a":utf8, 1, 2, 3>>
// just write
<<"a", 1, 2, 3>>
```

### Additional contract requirements

- String literals used as segments in a BitArray pattern (for example `<<"a", "b", _:bits>>`) are also treated as `utf8` when no encoding option is given.
