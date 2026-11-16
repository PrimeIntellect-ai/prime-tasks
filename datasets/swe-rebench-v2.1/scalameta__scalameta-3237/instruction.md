Tokens lacks bounds checking
An empty `Tokens` should throw on `head` and `last` and `apply` but does not when it avoids a bounds check on the underlying array. (`last` started throwing on 2.13.12.; `head` was also improved, so the override should use `super.head`.)
```
@data class Tokens private (
    private val tokens: Array[Token],
    private val start: Int,
    private val end: Int
) extends immutable.IndexedSeq[Token] with IndexedSeqOptimized[Token] {
  def apply(idx: Int): Token = tokens(start + idx)
  def length: Int = end - start
  override def slice(from: Int, until: Int): Tokens = {
    val lo = start + from.max(0).min(length)
    val hi = lo.max(start + until.min(length))
    Tokens(tokens, lo, hi)
  }

  /* Both head and headOption need to be implemented here due to
   * binary incompatibility caused by
   * https://github.com/scala/scala/commit/b20dd00b11f06c14c823d277cdfb58043a2586fc
   */
  override def head: Token = apply(0)

```

Noticed at https://github.com/scala/community-build/issues/1680#issuecomment-1625131437

### Additional contract requirements

- `scala.meta.tokens.Tokens` is an `IndexedSeq[Token]`. Its `apply(idx: Int): Token` returns the token at the zero-based position `idx` when `0 <= idx < length`, and otherwise throws `NoSuchElementException` whose message is `token $idx out of $length` (for example, `token 0 out of 0` for an empty collection).
- `Tokens.head: Token` returns the first token and throws `NoSuchElementException` whose message is `token 0 out of $length` when the collection is empty.
- `Tokens.last: Token` returns the last token and throws `NoSuchElementException` whose message is `token ${length - 1} out of $length` when the collection is empty (for an empty collection this message is `token -1 out of 0`).
- `scala.meta.Tree.tokens` returns a `Tokens` instance whose `head` and `last` are bounds-checked as described above.
