Unsupported SIP-64 syntax
It looks like https://github.com/scalameta/scalameta/pull/4068 didn't fix all SIP-64 cases

```
➜  ~ cat Test.scala
//> using dep org.scalameta::scalameta:4.12.2

import scala.meta._

object Main {
  def main(args: Array[String]): Unit = {
    val src = Input.String("""given List[Int] => Object {}""")
    val p = implicitly[parsers.Parse[Stat]]
    println(p.apply(src, dialects.Scala3).get.structure)
  }
}
```

```
➜  ~ scala Test.scala
Exception in thread "main" <input>:1: error: abstract givens cannot be anonymous
given List[Int] => Object {}
      ^
	at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:16)
	at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:9)
	at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
	at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:18)
	at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:9)
	at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
	at scala.meta.internal.parsers.ScalametaParser.givenDecl$$anonfun$1(ScalametaParser.scala:3536)
	at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:388)
	at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:393)
	at scala.meta.internal.parsers.ScalametaParser.givenDecl(ScalametaParser.scala:3539)
	at scala.meta.internal.parsers.ScalametaParser.defOrDclOrSecondaryCtor(ScalametaParser.scala:3421)
	at scala.meta.internal.parsers.ScalametaParser.nonLocalDefOrDcl(ScalametaParser.scala:3404)
	at scala.meta.internal.parsers.ScalametaParser$$anon$1.applyOrElse(ScalametaParser.scala:4264)
	at scala.meta.internal.parsers.ScalametaParser$$anon$1.applyOrElse(ScalametaParser.scala:4259)
	at scala.meta.internal.parsers.ScalametaParser.entrypointStat(ScalametaParser.scala:4289)
	at scala.meta.internal.parsers.ScalametaParser.parseStat$$anonfun$1(ScalametaParser.scala:70)
	at scala.meta.internal.parsers.ScalametaParser.parseRuleAfterBOF(ScalametaParser.scala:60)
	at scala.meta.internal.parsers.ScalametaParser.parseRule(ScalametaParser.scala:55)
	at scala.meta.internal.parsers.ScalametaParser.parseStat(ScalametaParser.scala:70)
	at scala.meta.parsers.Parse$.parseStat$lzyINIT1$$anonfun$1(Parse.scala:15)
	at scala.meta.parsers.Parse$$anon$1.apply(Parse.scala:37)
	at Main$.main(Test.scala:9)
	at Main.main(Test.scala)
```
