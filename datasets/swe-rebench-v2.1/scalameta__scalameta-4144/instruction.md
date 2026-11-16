Deprecated pointing to empty when using empty package
`deprecated => _empty_/` instead of `deprecated => scala/deprecated#` for:

```
@deprecated(since = "123")
class CLS(name: String) {
  def this(name2: Int) = this(name = name2.toString)
}
```

This only happens for Scala 2.13.x
