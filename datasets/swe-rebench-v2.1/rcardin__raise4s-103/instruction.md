Add a `values` extension function for `Iterable[Raise[Error] ?=> A]`
Add a `values` extension function for `Iterable[Raise[Error] ?=> A]`. The function must behave like the following:

```scala 3
val intermediateResults: List[Raise[String] ?=> Int] = List(1, 2, 3, 4).map(i => raise(i.toString))
val results: RaiseAcc[String] ?=> List[Int] = intermediateResults.values
```

### Additional contract requirements

- The extension works with any `Iterable` implementation, not only `List`, and produces a `RaiseAcc[Error]` context function returning `List[A]`.
- If every computation succeeds, the result contains their values in iterable traversal order. If computations raise errors, the `RaiseAcc` result reports all raised errors rather than stopping at the first one.
