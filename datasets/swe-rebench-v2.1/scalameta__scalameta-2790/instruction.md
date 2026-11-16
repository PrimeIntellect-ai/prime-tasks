Missing occurrence for reflective calls
```scala
❯ cat i414.scala
package minimized

object Issue414 {
  val x = new {
    val b = 1
  }
  x.b
}
❯ metac i414.scala
metawarning: 1 feature warning; re-run with -feature for details
1 warning
```

The generated SemanticDB is missing an occurrence for the reflective invocation of the anonymous class
```diff
❯ metap .
Summary:
Schema => SemanticDB v4
Uri => i414.scala
Text => empty
Language => Scala
Symbols => 4 entries
Occurrences => 6 entries

Symbols:
local0 => final class $anon extends AnyRef { +1 decls }
local1 => val method b: Int
minimized/Issue414. => final object Issue414 extends AnyRef { +1 decls }
minimized/Issue414.x. => val method x: AnyRef { val def b: Int }

Occurrences:
[0:8..0:17) <= minimized/
[2:7..2:15) <= minimized/Issue414.
[3:6..3:7) <= minimized/Issue414.x.
[3:14..3:14) <= local0
[4:8..4:9) <= local1
[6:2..6:3) => minimized/Issue414.x.
+ [6:5..6.6] => local1
```

I thought the occurrence was missing due how reflective calls get desugared but the desugaring isn't applied in typer
```
❯ scalac -Xprint:typer i414.scala -feature
i414.scala:4: error: not found: type int
  val x: { val b: int } = new {
                  ^
i414.scala:7: warning: reflective access of structural type member value b should be enabled
by making the implicit value scala.language.reflectiveCalls visible.
This can be achieved by adding the import clause 'import scala.language.reflectiveCalls'
or by setting the compiler option -language:reflectiveCalls.
See the Scaladoc for value scala.language.reflectiveCalls for a discussion
why the feature should be explicitly enabled.
  x.b
    ^
[[syntax trees at end of                     typer]] // i414.scala
package minimized {
  object Issue414 extends scala.AnyRef {
    def <init>(): minimized.Issue414.type = {
      Issue414.super.<init>();
      ()
    };
    private[this] val <x: error>: AnyRef{val b: <error>} = {
      final class $anon extends scala.AnyRef {
        def <init>(): <$anon: AnyRef> = {
          $anon.super.<init>();
          ()
        };
        private[this] val b: Int = 1;
        <stable> <accessor> def b: Int = $anon.this.b
      };
      new $anon()
    };
    <stable> <accessor> def <x: error>: AnyRef{val b: <error>} = Issue414.this.<x: error>;
    Issue414.this.<x: error>.<b: error>
  }
}

1 warning
1 error
```
The desugaring is applied after the jvm phase
```scala
❯ scalac -Xprint:jvm i414.scala -language:reflectiveCalls
i414.scala:7: warning: a pure expression does nothing in statement position; multiline expressions may require enclosing parentheses
  x.b
    ^
[[syntax trees at end of                       jvm]] // i414.scala
package minimized {
  object Issue414 extends Object {
    <synthetic> <static> def reflMethod$Method1(x$1: Class): reflect.Method = {
      var methodCache1: runtime.StructuralCallSite = <apply-dynamic>(apply#<none>, (bootstrap, classOf[]));
      var method1: reflect.Method = methodCache1.find(x$1);
      if (method1.ne(null))
        return method1
      else
        {
          method1 = scala.runtime.ScalaRunTime.ensureAccessible(x$1.getMethod("b", methodCache1.parameterTypes()));
          methodCache1.add(x$1, method1);
          return method1
        }
    };
    <static> private[this] val x: Object = _;
    <stable> <accessor> def x(): Object = Issue414.this.x;
    def <init>(): minimized.Issue414.type = {
      Issue414.super.<init>();
      Issue414.this.x = {
        new <$anon: Object>()
      };
      {
        val qual1: Object = Issue414.this.x();
        try {
  minimized.Issue414.reflMethod$Method1(qual1.getClass()).invoke(qual1, Array[Object]{})
} catch {
  case (1 @ (_: reflect.InvocationTargetException)) => throw 1.getCause()
}.$asInstanceOf[Integer]()
      };
      ()
    }
  };
  final class anon$1 extends Object {
    private[this] val b: Int = _;
    <stable> <accessor> def b(): Int = anon$1.this.b;
    def <init>(): <$anon: Object> = {
      anon$1.super.<init>();
      anon$1.this.b = 1;
      ()
    }
  }
}
```
