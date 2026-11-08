`illegal start of simple expression` error if `withAllowSignificantIndentation(false)`
`build.sbt`

```scala
libraryDependencies += "org.scalameta" %% "scalameta" % "4.12.5"

scalaVersion := "2.13.16"
```

`Main.scala`

```scala
import scala.meta._

object Main {
  def main(args: Array[String]): Unit = {
    val src = Input.String("""
def a: Int = c { [D] => e =>
  def f = e

  f
}
""")
    val p = implicitly[parsers.Parse[Stat]]
    println(
      p.apply(
        src,
        dialects.Scala3.withAllowSignificantIndentation(false)
      ).get.structure
    )
  }
}
```

```
[error] <input>:3: error: illegal start of simple expression
[error]   def f = e
[error]   ^
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr0(ScalametaParser.scala:2181)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr(ScalametaParser.scala:2151)
[error] 	at scala.meta.internal.parsers.ScalametaParser.prefixExpr(ScalametaParser.scala:2148)
[error] 	at scala.meta.internal.parsers.ScalametaParser.postfixExpr(ScalametaParser.scala:2012)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1646)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:332)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:386)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1567)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1470)
[error] 	at scala.meta.internal.parsers.ScalametaParser.termFunctionBody(ScalametaParser.scala:1740)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$exprOtherRest$7(ScalametaParser.scala:1728)
[error] 	at scala.Option.fold(Option.scala:263)
[error] 	at scala.meta.internal.parsers.ScalametaParser.exprOtherRest(ScalametaParser.scala:1724)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1647)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:332)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:386)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1567)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1470)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$polyFunction$1(ScalametaParser.scala:2191)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:328)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:383)
[error] 	at scala.meta.internal.parsers.ScalametaParser.polyFunction(ScalametaParser.scala:2188)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr0(ScalametaParser.scala:2180)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr(ScalametaParser.scala:2151)
[error] 	at scala.meta.internal.parsers.ScalametaParser.prefixExpr(ScalametaParser.scala:2148)
[error] 	at scala.meta.internal.parsers.ScalametaParser.postfixExpr(ScalametaParser.scala:2012)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1646)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:332)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:386)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1567)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$blockStatSeq$3(ScalametaParser.scala:4407)
[error] 	at scala.meta.internal.parsers.ScalametaParser.stat(ScalametaParser.scala:4289)
[error] 	at scala.meta.internal.parsers.ScalametaParser.getStat$1(ScalametaParser.scala:4407)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$blockStatSeq$5(ScalametaParser.scala:4412)
[error] 	at scala.meta.internal.parsers.ScalametaParser$.doWhile(ScalametaParser.scala:4480)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$blockStatSeq$1(ScalametaParser.scala:4412)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$blockStatSeq$1$adapted(ScalametaParser.scala:4385)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$listBy(ScalametaParser.scala:560)
[error] 	at scala.meta.internal.parsers.ScalametaParser.blockStatSeq(ScalametaParser.scala:4385)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$blockOnBrace$2(ScalametaParser.scala:2472)
[error] 	at scala.meta.internal.parsers.ScalametaParser.inBracesOnOpen(ScalametaParser.scala:267)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$blockOnBrace$1(ScalametaParser.scala:2470)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:328)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:383)
[error] 	at scala.meta.internal.parsers.ScalametaParser.blockOnBrace(ScalametaParser.scala:2470)
[error] 	at scala.meta.internal.parsers.ScalametaParser.blockOnBrace(ScalametaParser.scala:2472)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$blockExprOnBrace$1(ScalametaParser.scala:2475)
[error] 	at scala.meta.internal.parsers.ScalametaParser.blockExprPartial(ScalametaParser.scala:2454)
[error] 	at scala.meta.internal.parsers.ScalametaParser.blockExprOnBrace(ScalametaParser.scala:2474)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$getArgClauseOnBrace$1(ScalametaParser.scala:2407)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:328)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:383)
[error] 	at scala.meta.internal.parsers.ScalametaParser.getArgClauseOnBrace(ScalametaParser.scala:2406)
[error] 	at scala.meta.internal.parsers.ScalametaParser.argClause$1(ScalametaParser.scala:2254)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExprRest(ScalametaParser.scala:2255)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr0(ScalametaParser.scala:2183)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr(ScalametaParser.scala:2151)
[error] 	at scala.meta.internal.parsers.ScalametaParser.prefixExpr(ScalametaParser.scala:2148)
[error] 	at scala.meta.internal.parsers.ScalametaParser.postfixExpr(ScalametaParser.scala:2012)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1646)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:332)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:386)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1567)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1470)
[error] 	at scala.meta.internal.parsers.ScalametaParser.defn$1(ScalametaParser.scala:3786)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$funDefRest$1(ScalametaParser.scala:3790)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:388)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:393)
[error] 	at scala.meta.internal.parsers.ScalametaParser.funDefRest(ScalametaParser.scala:3770)
[error] 	at scala.meta.internal.parsers.ScalametaParser.funDefOrDclOrExtensionOrSecondaryCtor(ScalametaParser.scala:3741)
[error] 	at scala.meta.internal.parsers.ScalametaParser.defOrDclOrSecondaryCtor(ScalametaParser.scala:3437)
[error] 	at scala.meta.internal.parsers.ScalametaParser.nonLocalDefOrDcl(ScalametaParser.scala:3416)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.applyOrElse(ScalametaParser.scala:4258)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.applyOrElse(ScalametaParser.scala:4253)
[error] 	at scala.meta.internal.parsers.ScalametaParser.entrypointStat(ScalametaParser.scala:4283)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$parseStat$1(ScalametaParser.scala:70)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseRuleAfterBOF(ScalametaParser.scala:60)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseRule(ScalametaParser.scala:55)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseStat(ScalametaParser.scala:70)
[error] 	at scala.meta.parsers.Parse$.$anonfun$parseStat$1(Parse.scala:15)
[error] 	at scala.meta.parsers.Parse$$anon$1.apply(Parse.scala:37)
[error] 	at Main$.main(Main.scala:16)
[error] 	at Main.main(Main.scala)
```



### note

This is valid code in Scala 3.6.3-RC2

```
Welcome to Scala 3.6.3-RC2 (21.0.5, Java OpenJDK 64-Bit Server VM).
Type in expressions for evaluation. Or try :help.

scala> def c[B](x: [A] => (a: A) => B): Int = 2
     |
     | def a: Int = c { [D] => e =>
     |   def f = e
     |
     |   f
     | }
def c[B](x: [A] => (a: A) => B): Int
def a: Int
```
