'using' keyword is incorrectly repeated in pretty-printed syntax of class definition
```scala
@ import scala.meta.dialects.Scala3
import scala.meta.dialects.Scala3

@ val classDefn = q"class Foo(a: Int)(using x: Int, y: String) {}"
classDefn: Defn.Class = Defn.Class(
  mods = List(),
  name = Type.Name(value = "Foo"),
  tparams = List(),
  ctor = Ctor.Primary(
    mods = List(),
    name = _,
    paramss = List(
      List(Term.Param(mods = List(), name = Term.Name(value = "a"), decltpe = Some(value = Type.Name(value = "Int")), default = None)),
      List(Term.Param(mods = List(using), name = Term.Name(value = "x"), decltpe = Some(value = Type.Name(value = "Int")), default = None), Term.Param(mods = List(using), name = Term.Name(value = "y"), decltpe = Some(value = Type.Name(value = "String")), default = None))
    )
  ),
  templ = Template(early = List(), inits = List(), self = Self(name = _, decltpe = None), stats = List(), derives = List())
)

@ classDefn.syntax
res11: String = "class Foo(a: Int)(using x: Int, using y: String)"
```

Note how the `using` keyword is repeated for each parameter in the list, which is not valid Scala 3 syntax.

This problem only seems to occur for class definitions, not method definitions:

```scala
@ val defDefn = q"def foo(a: Int)(using x: Int, y: String) = a"
defDefn: Defn.Def = Defn.Def(
  mods = List(),
  name = Term.Name(value = "foo"),
  tparams = List(),
  paramss = List(
    List(Term.Param(mods = List(), name = Term.Name(value = "a"), decltpe = Some(value = Type.Name(value = "Int")), default = None)),
    List(Term.Param(mods = List(using), name = Term.Name(value = "x"), decltpe = Some(value = Type.Name(value = "Int")), default = None), Term.Param(mods = List(using), name = Term.Name(value = "y"), decltpe = Some(value = Type.Name(value = "String")), default = None))
  ),
  decltpe = None,
  body = Term.Name(value = "a")
)

@ defDefn.syntax
res13: String = "def foo(a: Int)(using x: Int, y: String) = a"
```
