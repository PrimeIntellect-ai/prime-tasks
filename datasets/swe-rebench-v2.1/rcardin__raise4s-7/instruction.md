Add a method to lift a value to Raise context
Add a method to lift a value of type `E` to the `Raise[E] ?=> T` context.
The method should look something like the following:

```scala 3
case object Error
def raiseFun: String raises Error = Error.raise[String]
```

### Additional contract requirements

- For a value `e` of type `E`, the expression `e.raise[T]` inside a `Raise[E]` context aborts the computation with `e` as the raised error, and it can be used where a value of type `T` is expected. For example, `Raise.either { "not found".raise[User] }` evaluates to `Left("not found")`.
- The method is available as `raise` in the public object `in.rcard.raise4s.RaiseAnyPredef`, so it can be imported with `import in.rcard.raise4s.RaiseAnyPredef.raise`.
