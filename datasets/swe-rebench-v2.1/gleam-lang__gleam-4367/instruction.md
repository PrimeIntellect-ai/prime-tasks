Variant inference does not work with `let assert`
When using `let assert` the compiler will not use the information that a variable should be narrowed when performing record field access or update:

Give this type:

```gleam
type Example {
  Wibble
  Wobble(x: Int, y: Int)
}
```

The following two snippets fail to type check:

```gleam
fn access_reproduction(example: Example) {
  let assert Wobble(x:, ..) = example

  example.x
}
```

```gleam
fn update_reproduction(example: Example) {
  let assert Wobble(x:, ..) = example

  Wobble(..example, x: x + 1)
}
```

With these errors:

```
error: Unknown record field
    ┌─ /...
    │
xyz │   example.x
    │           ^ This field does not exist

The value being accessed has this type:

    Example

It does not have fields that are common across all variants.

Note: The field you are trying to access is not defined consistently across
all variants of this custom type. To fix this, ensure that all variants
include the field with the same name, position, and type.
```

```
error: Unsafe record update
    ┌─ /...
    │
xyz │   Wobble(..example, x: x + 1)
    │            ^^^^^^^ I'm not sure this is always a `Wobble`


This value cannot be used to build an updated `Wobble` as it could be some
other variant.

Consider pattern matching on it with a case expression and then
constructing a new record with its values.
```

With the variant inference feature I would expect both examples to work
