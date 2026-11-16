ScalametaParser: comment before outdent not part of indented expression
In this example:
```
val (xTranslation, yTranslation) = (isHMirror, isVMirror) match
      case (true, true)  => ((rotationWidth / 2).toInt, (rotationHeight / 2).toInt)  // Top left
      case (true, false) => ((rotationHeight / 2).toInt, -(rotationWidth / 2).toInt) // Bottom left
      case (false, true) => (-(rotationHeight / 2).toInt, (rotationWidth / 2).toInt) // Top right
      case (false, false) => (-(rotationWidth / 2).toInt, -(rotationHeight / 2).toInt) // Bottom right
```
the `// Bottom right` comment *should* be part of the `Term.Match` but it only belongs to `Defn.Val` instead.

### Additional contract requirements

- The position of a match `Case` must also include its trailing line comment; for example, it must extend through `// c1` in `Case case (false, false) => (baz, qux) // c1`.
