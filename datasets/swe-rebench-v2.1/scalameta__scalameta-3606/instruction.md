[4.9.1] illegal start of simple expression
`build.sbt`


```scala
libraryDependencies += "org.scalameta" %% "scalameta" % "4.9.1"

scalaVersion := "2.13.13"
```

`Main.scala`

```scala
import scala.meta._

object Main {
  def main(args: Array[String]): Unit = {
    val src1 = Input.String(
"""
new A1 {
  def b1: C1 =
    ???
}
""")

    val src2 = Input.String(
"""
new A2 {
  def b2: C2 =
    ???

}
""")

    val p = implicitly[parsers.Parse[Stat]]

    // OK if there is no blank line
    println("src1 = " + p.apply(src1, dialects.Scala213Source3).get.structure)

    // NG if there is blank line
    println("src2 = " + p.apply(src2, dialects.Scala213Source3).get.structure)
  }
}
```

```
[info] running Main
src1 = Term.NewAnonymous(Template(Nil, List(Init(Type.Name("A1"), Name.Anonymous(), Nil)), Self(Name.Anonymous(), None), List(Defn.Def(Nil, Term.Name("b1"), Nil, Some(Type.Name("C1")), Term.Name("???"))), Nil))
[error] <input>:3: error: illegal start of simple expression
[error]   def b2: C2 =
[error]               ^
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr0(ScalametaParser.scala:2282)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr(ScalametaParser.scala:2235)
[error] 	at scala.meta.internal.parsers.ScalametaParser.prefixExpr(ScalametaParser.scala:2218)
[error] 	at scala.meta.internal.parsers.ScalametaParser.postfixExpr(ScalametaParser.scala:2097)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1694)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:319)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:366)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1599)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1498)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$funDefRest$1(ScalametaParser.scala:3906)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:368)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:373)
[error] 	at scala.meta.internal.parsers.ScalametaParser.funDefRest(ScalametaParser.scala:3868)
[error] 	at scala.meta.internal.parsers.ScalametaParser.funDefOrDclOrExtensionOrSecondaryCtor(ScalametaParser.scala:3813)
[error] 	at scala.meta.internal.parsers.ScalametaParser.defOrDclOrSecondaryCtor(ScalametaParser.scala:3643)
[error] 	at scala.meta.internal.parsers.ScalametaParser.nonLocalDefOrDcl(ScalametaParser.scala:3620)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$templateStat$1.applyOrElse(ScalametaParser.scala:4592)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$templateStat$1.applyOrElse(ScalametaParser.scala:4586)
[error] 	at scala.PartialFunction.$anonfun$runWith$1(PartialFunction.scala:231)
[error] 	at scala.PartialFunction.$anonfun$runWith$1$adapted(PartialFunction.scala:230)
[error] 	at scala.meta.internal.parsers.ScalametaParser.statSeqBuf(ScalametaParser.scala:4537)
[error] 	at scala.meta.internal.parsers.ScalametaParser.getStats$2(ScalametaParser.scala:4576)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$scala$meta$internal$parsers$ScalametaParser$$templateStatSeq$3(ScalametaParser.scala:4577)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$scala$meta$internal$parsers$ScalametaParser$$templateStatSeq$3$adapted(ScalametaParser.scala:4574)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$listBy(ScalametaParser.scala:581
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$templateStatSeq(ScalametaParser.scala:4574)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$templateStatSeq(ScalametaParser.scala:4566)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$templateBody$1(ScalametaParser.scala:4419)
[error] 	at scala.meta.internal.parsers.ScalametaParser.inBracesOr(ScalametaParser.scala:259)
[error] 	at scala.meta.internal.parsers.ScalametaParser.inBraces(ScalametaParser.scala:255)
[error] 	at scala.meta.internal.parsers.ScalametaParser.templateBody(ScalametaParser.scala:4419)
[error] 	at scala.meta.internal.parsers.ScalametaParser.templateBodyOpt(ScalametaParser.scala:4423)
[error] 	at scala.meta.internal.parsers.ScalametaParser.templateAfterExtends(ScalametaParser.scala:4366)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$template$1(ScalametaParser.scala:4387)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:316)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:365)
[error] 	at scala.meta.internal.parsers.ScalametaParser.template(ScalametaParser.scala:4374)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$simpleExpr0$2(ScalametaParser.scala:2269)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:316)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:365)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr0(ScalametaParser.scala:2267)
[error] 	at scala.meta.internal.parsers.ScalametaParser.simpleExpr(ScalametaParser.scala:2235)
[error] 	at scala.meta.internal.parsers.ScalametaParser.prefixExpr(ScalametaParser.scala:2218)
[error] 	at scala.meta.internal.parsers.ScalametaParser.postfixExpr(ScalametaParser.scala:2097)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$expr$2(ScalametaParser.scala:1694)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:319)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:366)
[error] 	at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1599)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.$anonfun$applyOrElse$1(ScalametaParser.scala:4481)
[error] 	at scala.meta.internal.parsers.ScalametaParser.stat(ScalametaParser.scala:4518)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.applyOrElse(ScalametaParser.scala:4481)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$1.applyOrElse(ScalametaParser.scala:4474)
[error] 	at scala.PartialFunction$Lifted.apply(PartialFunction.scala:338)
[error] 	at scala.PartialFunction$Lifted.apply(PartialFunction.scala:334)
[error] 	at scala.meta.internal.parsers.ScalametaParser.entrypointStat(ScalametaParser.scala:4511)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$parseStat$1(ScalametaParser.scala:69)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseRuleAfterBOF(ScalametaParser.scala:59)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseRule(ScalametaParser.scala:54)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseStat(ScalametaParser.scala:69)
[error] 	at scala.meta.parsers.Parse$.$anonfun$parseStat$1(Parse.scala:14)
[error] 	at scala.meta.parsers.Parse$$anon$1.apply(Parse.scala:36)
[error] 	at Main$.main(Main.scala:28)
[error] 	at Main.main(Main.scala)
```
