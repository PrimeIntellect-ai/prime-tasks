parse error since 4.8.0
### scalameta version

NG: 4.8.0 to 4.8.4
OK: 4.7.8

### `build.sbt`

```scala
libraryDependencies += "org.scalameta" %% "scalameta" % "4.8.4"

scalaVersion := "2.13.11"
```

### `Main.scala`

```scala
import scala.meta._

object Main {
  def main(args: Array[String]): Unit = {
    val src = Input.String(
"""
    A(
      b = new B,
      c =
        d,
      e = f
    )
"""
)
    val p = implicitly[parsers.Parse[Stat]]

    println(p.apply(src, dialects.Scala3).get.structure)
  }
}
```

### result `sbt run`

```
[info] running Main
[error] <input>:5: error: ; expected but , found
[error]         d,
[error]          ^
[error] 	at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:16)
[error] 	at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:16)
[error] 	at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
[error] 	at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:17)
[error] 	at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:17)
[error] 	at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
[error] 	at scala.meta.internal.parsers.ScalametaParser.syntaxErrorExpected(ScalametaParser.scala:367)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expect(ScalametaParser.scala:369)
[error] 	at scala.meta.internal.parsers.ScalametaParser.accept(ScalametaParser.scala:373)
[error] 	at scala.meta.internal.parsers.ScalametaParser.acceptStatSep(ScalametaParser.scala:389)
[error] 	at scala.meta.internal.parsers.ScalametaParser.iter$6(ScalametaParser.scala:4503)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$blockStatSeq$1(ScalametaParser.scala:4518)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$blockStatSeq$1$adapted(ScalametaParser.scala:4468)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$listBy(ScalametaParser.scala:505)
[error] 	at scala.meta.internal.parsers.ScalametaParser.blockStatSeq(ScalametaParser.scala:4468)
[error] 	at scala.meta.internal.parsers.ScalametaParser.blockWithinDelims(ScalametaParser.scala:2434)
[error] 	at scala.meta.internal.parsers.ScalametaParser.blockWithStats$1(ScalametaParser.scala:2437)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$block$1(ScalametaParser.scala:2442)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:300)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:346)
[error] 	at scala.meta.internal.parsers.ScalametaParser.block(ScalametaParser.scala:2436)
[error] 	at scala.meta.internal.parsers.ScalametaParser.blockExpr(ScalametaParser.scala:2430)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr0(ScalametaParser.scala:2203)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr(ScalametaParser.scala:2158)
[error] 	at scala.meta.internal.parsers.ScalametaParser.prefixExpr(ScalametaParser.scala:2141)
[error] 	at scala.meta.internal.parsers.ScalametaParser.postfixExpr(ScalametaParser.scala:2026)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1607)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:303)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:347)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1512)
[error] 	at scala.meta.internal.parsers.ScalametaParser.iter$2(ScalametaParser.scala:1634)
[error] 	at scala.meta.internal.parsers.ScalametaParser.exprOtherRest(ScalametaParser.scala:1662)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1608)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:303)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:347)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1512)
[error] 	at scala.meta.internal.parsers.ScalametaParser.argumentExpr(ScalametaParser.scala:2377)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$argumentExprsInParens$1(ScalametaParser.scala:2404)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$commaSeparated$1(ScalametaParser.scala:586)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$commaSeparated$1$adapted(ScalametaParser.scala:586)
[error] 	at scala.meta.internal.parsers.ScalametaParser.iter$1(ScalametaParser.scala:576)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$tokenSeparated$1(ScalametaParser.scala:582)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$tokenSeparated$1$adapted(ScalametaParser.scala:569)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$listBy(ScalametaParser.scala:505)
[error] 	at scala.meta.internal.parsers.ScalametaParser.tokenSeparated(ScalametaParser.scala:569)
[error] 	at scala.meta.internal.parsers.ScalametaParser.commaSeparatedWithIndex(ScalametaParser.scala:589)
[error] 	at scala.meta.internal.parsers.ScalametaParser.commaSeparated(ScalametaParser.scala:586)
[error] 	at scala.meta.internal.parsers.ScalametaParser.argumentExprsInParens(ScalametaParser.scala:2404)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$scala$meta$internal$parsers$ScalametaParser$$getArgClause$2(ScalametaParser.scala:2390)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$inParensAfterOpenOr(ScalametaParser.scala:238)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$inParensOnOpenOr(ScalametaParser.scala:229)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$scala$meta$internal$parsers$ScalametaParser$$getArgClause$1(ScalametaParser.scala:2391)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:300)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:346)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$getArgClause(ScalametaParser.scala:2380)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExprRest(ScalametaParser.scala:2288)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$simpleExpr0$3(ScalametaParser.scala:2208)
[error] 	at scala.util.Success.map(Try.scala:262)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr0(ScalametaParser.scala:2208)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr(ScalametaParser.scala:2158)
[error] 	at scala.meta.internal.parsers.ScalametaParser.prefixExpr(ScalametaParser.scala:2141)
[error] 	at scala.meta.internal.parsers.ScalametaParser.postfixExpr(ScalametaParser.scala:2026)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1607)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:303)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:347)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1512)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.$anonfun$applyOrElse$2(ScalametaParser.scala:4301)
[error] 	at scala.meta.internal.parsers.ScalametaParser.stat(ScalametaParser.scala:4338)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.applyOrElse(ScalametaParser.scala:4301)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.applyOrElse(ScalametaParser.scala:4294)
[error] 	at scala.PartialFunction$Lifted.apply(PartialFunction.scala:338)
[error] 	at scala.PartialFunction$Lifted.apply(PartialFunction.scala:334)
[error] 	at scala.meta.internal.parsers.ScalametaParser.entrypointStat(ScalametaParser.scala:4331)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$parseStat$1(ScalametaParser.scala:61)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseRuleAfterBOF(ScalametaParser.scala:51)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseRule(ScalametaParser.scala:46)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseStat(ScalametaParser.scala:61)
[error] 	at scala.meta.parsers.Parse$.$anonfun$parseStat$1(Parse.scala:14)
[error] 	at scala.meta.parsers.Parse$$anon$1.apply(Parse.scala:36)
[error] 	at Main$.main(Main.scala:17)
```

### run with scalameta 4.7.8

```
Term.Apply(Term.Name("A"), Term.ArgClause(List(Term.Assign(Term.Name("b"), Term.New(Init(Type.Name("B"), Name(""), Nil))), Term.Assign(Term.Name("c"), Term.Name("d")), Term.Assign(Term.Name("e"), Term.Name("f"))), None))
```
