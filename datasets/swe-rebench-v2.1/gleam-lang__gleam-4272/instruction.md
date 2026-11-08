"Convert to pipe" code action interacts weirdly with `use`
The new "Convert to pipe" code action doesn't properly take into account `use` expressions. For example, given this code:
```gleam
import gleam/result

pub fn main() {
  use x <- result.try(todo)
  Ok(x + 1)
}
```

The Language Server offers a code action to transform it into this:

```gleam
import gleam/result

pub fn main() {
  Ok(x + 1) |> use x <- result.try(todo)
  _
}
```

Which is not how `use` works.

### Additional contract requirements

The action must not transform an expression in a `use` body into a pipe whose right-hand side is the surrounding `use` expression. A safe conversion of an eligible ordinary function call in the body of a `use` expression must remain available, and it must leave the surrounding `use` expression unchanged.
