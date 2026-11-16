Rename the `bind()` method into`value`
Rename the `bind()` method into `value` for the `Either`, `Option`, and `Try` types.
Instead of:

```scala 3
def foo: Int raises String = Right(1).bind()
```

it should be possible the following:

```scala 3
def foo: Int raises String = Right(1).value
```

### Additional contract requirements

- The `value` operation for `Either`, `Option`, and `Try` is provided as an extension method in the `in.rcard.raise4s.Bind` object, so that it can be brought into scope with `import in.rcard.raise4s.Bind.value`.
- `Either.value` returns the `Right` value and raises the `Left` value as an error in the enclosing `Raise` context.
- `Option.value` returns the `Some` value and raises `None` as an error in the enclosing `Raise` context.
- `Try.value` returns the `Success` value and raises the `Failure` exception as an error in the enclosing `Raise` context.
