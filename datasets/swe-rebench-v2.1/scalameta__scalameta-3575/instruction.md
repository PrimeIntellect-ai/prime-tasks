`illegal start of simple expression` error since 4.8.15
- failure: 4.8.15, 4.9.0
- success: 4.8.14

`build.sbt`


```scala
libraryDependencies += "org.scalameta" %% "scalameta" % "4.8.15"

scalaVersion := "2.13.12"
```

`Main.scala`

```scala
import scala.meta._

object Main {
  def main(args: Array[String]): Unit = {
    val src = Input.String(
"""
  new A {
    def b: C =
      ???
  }
""")
    val p = implicitly[parsers.Parse[Stat]]

    println(p.apply(src, dialects.Scala213Source3).get.structure)
  }
}
```

```
[info] running Main
[error] <input>:3: error: illegal start of simple expression
[error]     def b: C =
[error]               ^
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr0(ScalametaParser.scala:2270)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr(ScalametaParser.scala:2223)
[error] 	at scala.meta.internal.parsers.ScalametaParser.prefixExpr(ScalametaParser.scala:2206)
[error] 	at scala.meta.internal.parsers.ScalametaParser.postfixExpr(ScalametaParser.scala:2081)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1676)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:322)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:366)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1581)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1480)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$funDefRest$1(ScalametaParser.scala:3807)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:368)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:373)
[error] 	at scala.meta.internal.parsers.ScalametaParser.funDefRest(ScalametaParser.scala:3769)
[error] 	at scala.meta.internal.parsers.ScalametaParser.funDefOrDclOrExtensionOrSecondaryCtor(ScalametaParser.scala:3714)
[error] 	at scala.meta.internal.parsers.ScalametaParser.defOrDclOrSecondaryCtor(ScalametaParser.scala:3544)
[error] 	at scala.meta.internal.parsers.ScalametaParser.nonLocalDefOrDcl(ScalametaParser.scala:3523)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$templateStat$1.applyOrElse(ScalametaParser.scala:4495)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$templateStat$1.applyOrElse(ScalametaParser.scala:4489)
[error] 	at scala.PartialFunction.$anonfun$runWith$1(PartialFunction.scala:231)
[error] 	at scala.PartialFunction.$anonfun$runWith$1$adapted(PartialFunction.scala:230)
[error] 	at scala.meta.internal.parsers.ScalametaParser.statSeqBuf(ScalametaParser.scala:4440)
[error] 	at scala.meta.internal.parsers.ScalametaParser.getStats$2(ScalametaParser.scala:4479)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$scala$meta$internal$parsers$ScalametaParser$$templateStatSeq$3(ScalametaParser.scala:4480)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$scala$meta$internal$parsers$ScalametaParser$$templateStatSeq$3$adapted(ScalametaParser.scala:4477)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$listBy(ScalametaParser.scala:567
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$templateStatSeq(ScalametaParser.scala:4477)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$templateStatSeq(ScalametaParser.scala:4469)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$templateBody$1(ScalametaParser.scala:4322)
[error] 	at scala.meta.internal.parsers.ScalametaParser.inBracesOr(ScalametaParser.scala:260)
[error] 	at scala.meta.internal.parsers.ScalametaParser.inBraces(ScalametaParser.scala:256)
[error] 	at scala.meta.internal.parsers.ScalametaParser.templateBody(ScalametaParser.scala:4322)
[error] 	at scala.meta.internal.parsers.ScalametaParser.templateBodyOpt(ScalametaParser.scala:4326)
[error] 	at scala.meta.internal.parsers.ScalametaParser.templateAfterExtends(ScalametaParser.scala:4269)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$template$1(ScalametaParser.scala:4290)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:319)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:365)
[error] 	at scala.meta.internal.parsers.ScalametaParser.template(ScalametaParser.scala:4277)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$simpleExpr0$2(ScalametaParser.scala:2257)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:319)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:365)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr0(ScalametaParser.scala:2255)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr(ScalametaParser.scala:2223)
[error] 	at scala.meta.internal.parsers.ScalametaParser.prefixExpr(ScalametaParser.scala:2206)
[error] 	at scala.meta.internal.parsers.ScalametaParser.postfixExpr(ScalametaParser.scala:2081)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1676)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:322)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:366)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1581)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.$anonfun$applyOrElse$2(ScalametaParser.scala:4384)
[error] 	at scala.meta.internal.parsers.ScalametaParser.stat(ScalametaParser.scala:4421)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.applyOrElse(ScalametaParser.scala:4384)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.applyOrElse(ScalametaParser.scala:4377)
[error] 	at scala.PartialFunction$Lifted.apply(PartialFunction.scala:338)
[error] 	at scala.PartialFunction$Lifted.apply(PartialFunction.scala:334)
[error] 	at scala.meta.internal.parsers.ScalametaParser.entrypointStat(ScalametaParser.scala:4414)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$parseStat$1(ScalametaParser.scala:69)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseRuleAfterBOF(ScalametaParser.scala:59)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseRule(ScalametaParser.scala:54)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseStat(ScalametaParser.scala:69)
[error] 	at scala.meta.parsers.Parse$.$anonfun$parseStat$1(Parse.scala:14)
[error] 	at scala.meta.parsers.Parse$$anon$1.apply(Parse.scala:36)
[error] 	at Main$.main(Main.scala:14)
[error] 	at Main.main(Main.scala)
```
