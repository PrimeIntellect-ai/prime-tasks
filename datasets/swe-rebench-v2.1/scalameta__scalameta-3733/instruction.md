Type apply after block fails to parse
The following snippet is valid in Scala 3:

```Scala
def fn[A](a: A) = ???
{
  [B] => (c: B) => fn[B](c)
}[Int](0)
```

Scalameta parser fails to parse it with:
```
`;` expected but `[` found
```
