Scala 3 indentation syntax: False positive "outdent expected" error
### Describe the bug

To reproduce:

1. Write this

```scala
//> using scala 3.5.2

def demo: Option[Unit] =
  for
    _ <- Option(42).map: _ =>
      ???

    _ <- Option(42)
  yield ()

```

2. There's an error at the second `<-`

<img width="635" alt="image" src="https://github.com/user-attachments/assets/d03788ec-5d5e-4443-a2e9-9734649c5c8d">


### Expected behavior

No error

### Operating system

macOS

### Editor/Extension

VS Code

### Version of Metals

v1.4.0

### Extra context or search terms

- works fine in 1.3.5
- compiler is happy with the syntax
- removing the empty line between the generators, or replacing it with a comment, removes the error
