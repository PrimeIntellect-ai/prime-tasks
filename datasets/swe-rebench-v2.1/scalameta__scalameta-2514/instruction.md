scala3: fails to parse TryWithHandler if catch followed by NL
The following snippet fails parsing with scala3 dialect:
```
  try
    a
  catch
    bar
  finally
    a
```
according to https://docs.scala-lang.org/scala3/reference/syntax.html#expressions, it looks like `catch` can be followed by any expression (not just `case`) and doesn't prohibit newline.
