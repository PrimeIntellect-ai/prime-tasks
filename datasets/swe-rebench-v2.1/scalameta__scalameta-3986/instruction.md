`Wildcard import must be in the last position` error
`build.sbt`

```scala
libraryDependencies += "org.scalameta" %% "scalameta" % "4.10.1"

scalaVersion := "2.13.15"
```

`Main.scala`

```scala
import scala.meta._

object Main {
  def main(args: Array[String]): Unit = {
    val src = Input.String("""import scala.{ _ , given }""")
    val p = implicitly[parsers.Parse[Source]]
    println(p.apply(src, dialects.Scala212Source3).get.structure)
  }
}
```

This is valid code in Scala 2.12.20 with `-Xsource:3`

- https://github.com/scala/scala/pull/9736

```
$ scala -Xsource:3
Welcome to Scala 2.12.20 (OpenJDK 64-Bit Server VM, Java 21.0.4).
Type in expressions for evaluation. Or try :help.

scala> import scala.{ _ , given }
import scala._
```


```
[error] <input>:1: error: Wildcard import must be in the last position
[error] import scala.{ _ , given }
[error]                ^
[error] 	at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:16)
[error] 	at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:16)
[error] 	at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$importees$2(ScalametaParser.scala:3192)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$importees$2$adapted(ScalametaParser.scala:3190)
[error] 	at scala.collection.immutable.List.foreach(List.scala:334)
[error] 	at scala.meta.internal.parsers.ScalametaParser.importees(ScalametaParser.scala:3190)
[error] 	at scala.meta.internal.parsers.ScalametaParser.dotselectors$1(ScalametaParser.scala:3162)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$importer$1(ScalametaParser.scala:3175)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:322)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:370)
[error] 	at scala.meta.internal.parsers.ScalametaParser.importer(ScalametaParser.scala:3156)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$importStmt$2(ScalametaParser.scala:3153)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$commaSeparated$1(ScalametaParser.scala:606)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$commaSeparated$1$adapted(ScalametaParser.scala:606)
[error] 	at scala.meta.internal.parsers.ScalametaParser.iter$1(ScalametaParser.scala:596)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$tokenSeparated$1(ScalametaParser.scala:601)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$tokenSeparated$1$adapted(ScalametaParser.scala:589)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$listBy(ScalametaParser.scala:529)
[error] 	at scala.meta.internal.parsers.ScalametaParser.tokenSeparated(ScalametaParser.scala:589)
[error] 	at scala.meta.internal.parsers.ScalametaParser.commaSeparatedWithIndex(ScalametaParser.scala:610)
[error] 	at scala.meta.internal.parsers.ScalametaParser.commaSeparated(ScalametaParser.scala:606)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$importStmt$1(ScalametaParser.scala:3153)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:322)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:370)
[error] 	at scala.meta.internal.parsers.ScalametaParser.importStmt(ScalametaParser.scala:3151)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$2.applyOrElse(ScalametaParser.scala:4034)
[error] 	at scala.meta.internal.parsers.ScalametaParser$$anonfun$2.applyOrElse(ScalametaParser.scala:4030)
[error] 	at scala.PartialFunction.$anonfun$runWith$1(PartialFunction.scala:231)
[error] 	at scala.PartialFunction.$anonfun$runWith$1$adapted(PartialFunction.scala:230)
[error] 	at scala.meta.internal.parsers.ScalametaParser.statSeqBuf(ScalametaParser.scala:4023)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$statSeq$1(ScalametaParser.scala:4012)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$statSeq$1$adapted(ScalametaParser.scala:4012)
[error] 	at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$listBy(ScalametaParser.scala:529)
[error] 	at scala.meta.internal.parsers.ScalametaParser.statSeq(ScalametaParser.scala:4012)
[error] 	at scala.meta.internal.parsers.ScalametaParser.bracelessPackageStats$1(ScalametaParser.scala:4183)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$source$1(ScalametaParser.scala:4186)
[error] 	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:322)
[error] 	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:370)
[error] 	at scala.meta.internal.parsers.ScalametaParser.source(ScalametaParser.scala:4151)
[error] 	at scala.meta.internal.parsers.ScalametaParser.entrypointSource(ScalametaParser.scala:4189)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseSourceImpl(ScalametaParser.scala:119)
[error] 	at scala.meta.internal.parsers.ScalametaParser.$anonfun$parseSource$1(ScalametaParser.scala:116)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseRuleAfterBOF(ScalametaParser.scala:58)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseRule(ScalametaParser.scala:53)
[error] 	at scala.meta.internal.parsers.ScalametaParser.parseSource(ScalametaParser.scala:116)
[error] 	at scala.meta.parsers.Parse$.$anonfun$parseSource$1(Parse.scala:30)
[error] 	at scala.meta.parsers.Parse$$anon$1.apply(Parse.scala:37)
[error] 	at Main$.main(Main.scala:7)
[error] 	at Main.main(Main.scala)
```
