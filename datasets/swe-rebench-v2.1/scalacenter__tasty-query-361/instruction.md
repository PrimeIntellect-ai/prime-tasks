Support references to type lambda parameters inside parameters themselves
A simple example:

```scala
class GrowableBuilder[Elem, To <: Growable[Elem]]
```

A harder example with the param, referencing itself:
```scala
class Boxxy[I <: Int, B <: Boxxy[I, B]]
```
