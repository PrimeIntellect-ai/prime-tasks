Parse error on polymorphic lambda when it appears inside a block
# Minimization
```scala
//> using dep org.scalameta::scalameta:4.13.4

import scala.meta.*

@main def Test =
  val program1 = """
def foo =
  [T] => (a: T) => a"""

  val program2 = """
def foo =
  println()
  [T] => (a: T) => a"""

  val tree1 = dialects.Scala3(program1).parse[Source].get // ok
  val tree2 = dialects.Scala3(program2).parse[Source].get // error
```

# Output
```scala
Exception in thread "main" <input>:4: error: `;` expected but `=>` found
  [T] => (a: T) => a
      ^
        at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:16)
        at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:9)
        at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
        at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:17)
        at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:9)
        at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
        at scala.meta.internal.parsers.ScalametaParser.syntaxErrorExpected(ScalametaParser.scala:425)
        at scala.meta.internal.parsers.ScalametaParser.syntaxErrorExpected(ScalametaParser.scala:423)
        at scala.meta.internal.parsers.ScalametaParser.acceptStatSep(ScalametaParser.scala:502)
        at scala.meta.internal.parsers.ScalametaParser.blockStatSeq$$anonfun$1$$anonfun$2(ScalametaParser.scala:4340)
        at scala.Function0.apply$mcZ$sp(Function0.scala:42)
        at scala.meta.internal.parsers.ScalametaParser$.doWhile(ScalametaParser.scala:4409)
        at scala.meta.internal.parsers.ScalametaParser.blockStatSeq$$anonfun$1(ScalametaParser.scala:4340)
        at scala.runtime.function.JProcedure1.apply(JProcedure1.java:15)
        at scala.runtime.function.JProcedure1.apply(JProcedure1.java:10)
        at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$listBy(ScalametaParser.scala:555)
        at scala.meta.internal.parsers.ScalametaParser.blockStatSeq(ScalametaParser.scala:4313)
        at scala.meta.internal.parsers.ScalametaParser.blockOnIndent$$anonfun$1$$anonfun$1(ScalametaParser.scala:2400)
        at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$indentedOnOpen(ScalametaParser.scala:274)
        at scala.meta.internal.parsers.ScalametaParser.blockOnIndent$$anonfun$1(ScalametaParser.scala:2403)
        at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:328)
        at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:382)
        at scala.meta.internal.parsers.ScalametaParser.blockOnIndent(ScalametaParser.scala:2404)
        at scala.meta.internal.parsers.ScalametaParser.blockExprOnIndent$$anonfun$1(ScalametaParser.scala:2407)
        at scala.meta.internal.parsers.ScalametaParser.blockExprPartial(ScalametaParser.scala:2393)
        at scala.meta.internal.parsers.ScalametaParser.blockExprOnIndent(ScalametaParser.scala:2407)
        at scala.meta.internal.parsers.ScalametaParser.simpleExpr0(ScalametaParser.scala:2117)
        at scala.meta.internal.parsers.ScalametaParser.simpleExpr(ScalametaParser.scala:2100)
        at scala.meta.internal.parsers.ScalametaParser.prefixExpr(ScalametaParser.scala:2097)
        at scala.meta.internal.parsers.ScalametaParser.postfixExpr(ScalametaParser.scala:1962)
        at scala.meta.internal.parsers.ScalametaParser.$anonfun$38(ScalametaParser.scala:1597)
        at scala.meta.internal.parsers.ScalametaParser.atPosOpt(ScalametaParser.scala:328)
        at scala.meta.internal.parsers.ScalametaParser.autoPosOpt(ScalametaParser.scala:382)
        at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1600)
        at scala.meta.internal.parsers.ScalametaParser.expr(ScalametaParser.scala:1417)
        at scala.meta.internal.parsers.ScalametaParser.defn$1(ScalametaParser.scala:3720)
        at scala.meta.internal.parsers.ScalametaParser.funDefRest$$anonfun$1(ScalametaParser.scala:3724)
        at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:384)
        at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:389)
        at scala.meta.internal.parsers.ScalametaParser.funDefRest(ScalametaParser.scala:3729)
        at scala.meta.internal.parsers.ScalametaParser.funDefOrDclOrExtensionOrSecondaryCtor(ScalametaParser.scala:3675)
        at scala.meta.internal.parsers.ScalametaParser.defOrDclOrSecondaryCtor(ScalametaParser.scala:3371)
        at scala.meta.internal.parsers.ScalametaParser.nonLocalDefOrDcl(ScalametaParser.scala:3350)
        at scala.meta.internal.parsers.ScalametaParser$$anon$2.applyOrElse(ScalametaParser.scala:4249)
        at scala.meta.internal.parsers.ScalametaParser$$anon$2.applyOrElse(ScalametaParser.scala:4241)
        at scala.PartialFunction.$anonfun$runWith$1(PartialFunction.scala:231)
        at scala.PartialFunction.$anonfun$runWith$1$adapted(PartialFunction.scala:230)
        at scala.meta.internal.parsers.ScalametaParser.statSeqBuf(ScalametaParser.scala:4234)
        at scala.meta.internal.parsers.ScalametaParser.statSeq$$anonfun$1(ScalametaParser.scala:4223)
        at scala.runtime.function.JProcedure1.apply(JProcedure1.java:15)
        at scala.runtime.function.JProcedure1.apply(JProcedure1.java:10)
        at scala.meta.internal.parsers.ScalametaParser.scala$meta$internal$parsers$ScalametaParser$$listBy(ScalametaParser.scala:555)
        at scala.meta.internal.parsers.ScalametaParser.statSeq(ScalametaParser.scala:4223)
        at scala.meta.internal.parsers.ScalametaParser.bracelessPackageStats$1(ScalametaParser.scala:4393)
        at scala.meta.internal.parsers.ScalametaParser.source$$anonfun$1(ScalametaParser.scala:4396)
        at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:324)
        at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:379)
        at scala.meta.internal.parsers.ScalametaParser.source(ScalametaParser.scala:4397)
        at scala.meta.internal.parsers.ScalametaParser.entrypointSource(ScalametaParser.scala:4399)
        at scala.meta.internal.parsers.ScalametaParser.parseSourceImpl(ScalametaParser.scala:114)
        at scala.meta.internal.parsers.ScalametaParser.parseSource$$anonfun$1(ScalametaParser.scala:111)
        at scala.meta.internal.parsers.ScalametaParser.parseRuleAfterBOF(ScalametaParser.scala:60)
        at scala.meta.internal.parsers.ScalametaParser.parseRule(ScalametaParser.scala:55)
        at scala.meta.internal.parsers.ScalametaParser.parseSource(ScalametaParser.scala:111)
        at scala.meta.parsers.Parse$.parseSource$lzyINIT1$$anonfun$1(Parse.scala:30)
        at scala.meta.parsers.Parse$$anon$1.apply(Parse.scala:37)
        at scala.meta.parsers.Api$XtensionParseDialectInput.parse(Api.scala:22)
        at a$package$.Test(a.scala:16)
        at Test.main(a.scala:5)
```

# Expected Output

No error since this is parsed correctly by the compiler.
