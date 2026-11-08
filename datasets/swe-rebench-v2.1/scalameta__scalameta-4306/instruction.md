Bad 2.x invalid parse error w/ extra newline before generic param of super type
Consider the following scala code:
```scala
trait F[A]
trait B extends F
  [Int]
```
Although miserably formatted, it should parse as `trait F` and `trait B` in at least Scala 2.12, 2.13, 3.6 (I think all Scala versions, but I'm not sure). However, Scalameta doesn't like it:

```
scala> "trait F[A]\ntrait B extends F\n  [Int]".parse[Source].get
scala.meta.parsers.ParseException: <input>:3: error: illegal start of definition `[`
  [Int]
  ^
  at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:16)
  at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:16)
  at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
  at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:17)
  at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:17)
  at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
  at scala.meta.internal.parsers.ScalametaParser.statSeqBuf(ScalametaParser.scala:4236)
  at scala.meta.internal.parsers.ScalametaParser.$anonfun$statSeq$1(ScalametaParser.scala:4224)
  at scala.meta.internal.parsers.ScalametaParser.$anonfun$statSeq$1$adapted(ScalametaParser.scala:4224)
  at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$listBy(ScalametaParser.scala:555)
  at scala.meta.internal.parsers.ScalametaParser.statSeq(ScalametaParser.scala:4224)
  at scala.meta.internal.parsers.ScalametaParser.bracelessPackageStats$1(ScalametaParser.scala:4394)
  at scala.meta.internal.parsers.ScalametaParser.$anonfun$source$1(ScalametaParser.scala:4397)
  at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:324)
  at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:379)
  at scala.meta.internal.parsers.ScalametaParser.source(ScalametaParser.scala:4362)
  at scala.meta.internal.parsers.ScalametaParser.entrypointSource(ScalametaParser.scala:4400)
  at scala.meta.internal.parsers.ScalametaParser.parseSourceImpl(ScalametaParser.scala:114)
  at scala.meta.internal.parsers.ScalametaParser.$anonfun$parseSource$1(ScalametaParser.scala:111)
  at scala.meta.internal.parsers.ScalametaParser.parseRuleAfterBOF(ScalametaParser.scala:60)
  at scala.meta.internal.parsers.ScalametaParser.parseRule(ScalametaParser.scala:55)
  at scala.meta.internal.parsers.ScalametaParser.parseSource(ScalametaParser.scala:111)
  at scala.meta.parsers.Parse$.$anonfun$parseSource$1(Parse.scala:30)
  at scala.meta.parsers.Parse$$anon$1.apply(Parse.scala:37)
  at scala.meta.parsers.Api$XtensionParseDialectInput.parse(Api.scala:22)
  at scala.meta.parsers.Api$XtensionParseInputLike.parse(Api.scala:13)
  ... 59 elided
```

### Additional contract requirements

- In the Scala 3 dialect, however, `trait B extends F\n[Int]` must fail with `error: illegal start of definition `[`.
