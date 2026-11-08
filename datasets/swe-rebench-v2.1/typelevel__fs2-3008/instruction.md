fs2.text.encode adds too many BOMs for UTF-16
Reproducer: https://scastie.scala-lang.org/kPRHfJXRQCyB4Y9GYgziVQ

```scala
Stream("1", "2", "3").through(encode(StandardCharsets.UTF_16)).compile.to(List)
// gives: List(-2, -1, 0, 49, -2, -1, 0, 50, -2, -1, 0, 51)
```

The `-2, -1` slices are BOMs added as `StandardCharsets.UTF_16` emits them when encoding. Only the first one is valid, the ones at the string boundaries should not be emitted.

### Additional contract requirements

- When a character cannot be represented by the selected charset, replace it with that charset’s replacement sequence. In particular, encoding `à` as ASCII must produce `List(63).map(_.toByte)`.
