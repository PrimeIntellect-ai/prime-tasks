Scaladoc param name is incorrect when description is started on next line
The following doc comment is currently not parsed correctly.
```
/**
  *   @param x
  *       This is a really long description
  */
case class A(x: String)
```

The name is parsed to `x\nThis` and the body `is a really long description` correct should be that the name is `x` and the body should be `This is a really long description`.
