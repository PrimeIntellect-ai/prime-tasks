Go to definition breaks in for comprehensions containing .unapply calls
### Describe the bug

An attempt to go to the definition of `foo` or `bar` in the following for comprehension leads to the `Option.withFilter` method
```scala
object GoToDefinitionWithFilterBug {
  case class Foo()
  val foo: Option[Foo] = None
  val bar: Option[(String, String)] = None

  for {
    Foo() <- foo // try going to definition on `foo`
    (_, _) <- bar // or on `bar`
  } yield ()
}
```
The bug seems to appear in expressions with calls to `.unapply` methods.

Actually, found it [here](https://github.com/scalameta/metals/blob/f8077f466130debd7d1fc7cb9a52f86d15b83f88/metals/src/main/scala/scala/meta/internal/rename/RenameProvider.scala#L80) while wandering over the Metals codebase

### Expected behavior

Go to definition results in going to actual definitions instead of `Option.withFilter`

### Operating system

Linux

### Editor/Extension

Nvim (nvim-metals)

### Version of Metals

v0.11.9

### Extra context or search terms

_No response_

### Additional contract requirements

- Add a public val `x` of type `Option[(Int, Int)]` in class `example.ForComprehension`, used as the generator of a for-comprehension. Its symbol is `example/ForComprehension#x.`.
- In object `n.ForCompWithFilter`, a val `foo` of type `Option[(Int, Int)]` used as the generator of a for-comprehension resolves to its own definition symbol `n/ForCompWithFilter.foo.`.
- A val `foo` of type `Option[Foo]` used as the generator of a for-comprehension with a `Foo()` extractor pattern resolves to its own definition symbol `o/ForCompWithExtractor.foo.`.
