Using `use` together with pattern matches compiles, when it shouldn't
The following code compiles, when it shouldn't:
```gleam
import gleam/io
import gleam/result

pub fn main() {
  use <<var:8>> <- result.try(wibble())
  Ok(io.debug(var))
}

fn wibble() -> Result(BitArray, Nil) {
  Ok(<<42, 0>>)
}
```

On Erlang, it will result in a runtime error, while on JS, it will just print `42`.

Gleam version 1.6.1

### Additional contract requirements

- For the input `use [1, 2, 3] <- todo` followed by `todo`, report this diagnostic with the exact title and message:

```text
error: Inexhaustive pattern
  ┌─ /src/one/two.gleam:2:5
  │
2 │ use [1, 2, 3] <- todo
  │     ^^^^^^^^^

This assignment uses a pattern that does not match all possible values. If
one of the other values is used then the assignment will crash.

The missing patterns are:

    []
    [_, _, _, _, ..]
    [_, _, _]
    [_, _]
    [_]

Hint: Use a more general pattern or use `let assert` instead.
```

- When the input `use [1, 2, 3] <- todo` is followed by `use <<var:8>> <- todo` and then `todo`, the bit-array pattern is also reported as inexhaustive, with this exact title and message:

```text
error: Inexhaustive pattern
  ┌─ /src/one/two.gleam:3:5
  │
3 │ use <<var:8>> <- todo
  │     ^^^^^^^^^

This assignment uses a pattern that does not match all possible values. If
one of the other values is used then the assignment will crash.

The missing patterns are:

    _

Hint: Use a more general pattern or use `let assert` instead.
```
