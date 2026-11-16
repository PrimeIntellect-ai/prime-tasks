"Qualify `x` as `wibble.x` code action does not respect shadowing.
Gleam encourages the reuse of meaningful variable names through shadowing, be that through `let` bindings, pattern matching, or lambda argument names. When triggering the code action to qualify a function with its module name, the transformation is applied to **any** variable that matches the unqualified name, even if it is an unrelated shadowing:

```gleam
import wibble.{x}

fn example() {
  echo x
       ^ place cursor here

  let x = 1

  echo x

  let cb = fn(x) {
    echo x
  }

  todo
}
```

Triggering the code action at the cursor position indicator above results in the following module:

```gleam
import wibble

fn example() {
  echo wibble.x

  let x = 1

  echo wibble.x

  let cb = fn(x) {
    echo wibble.x
  }

  todo
}
```

I would **expect** the module to look like this:

```gleam
import wibble.{x}

fn example() {
  echo wibble.x

  let x = 1

  echo x

  let cb = fn(x) {
    echo x
  }

  todo
}
```

It is important to note that placing my cursor on any of the shadowed `x` uses will **not let me trigger the code action** because the LSP is aware that these are not the same `x`.

I ran into this refactoring some tests and ended up undoing the action and manually updating things as the amount of incorrect renames was much higher.

### Additional contract requirements

- Shadowing introduced through pattern matching (for example a `case` pattern
  that binds the same name) must also be left unqualified, exactly like `let`
  bindings and lambda argument names.
