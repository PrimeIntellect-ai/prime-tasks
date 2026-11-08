"failed to generate semanticdb for" error for Scala 3 syntax in Scala 2 (with `-Xsource:3` enabled)
Minimal repro:

### build.sbt:
```scala
inThisBuild(
  List(
    scalaVersion := "2.13.6",
    semanticdbEnabled := true,
    scalacOptions += "-Xsource:3"
  )
)
```

### Main.scala
```scala
object Hello {
  val x = "hello"
     ++ "world"
}
```

This syntax compiles fine on Scala 2 with `-Xsource:3` enabled, but when also enabling SemanticDB, results in the following error:
```
.../Main.scala:8: error: ; expected but string constant found
    ++ "world"
       ^
```

### Full stack trace:
<details>

```
scalac: failed to generate semanticdb for /Users/hmemcpy/git/sbt-playground/src/main/scala/app/Main.scala:
/Users/hmemcpy/git/sbt-playground/src/main/scala/app/Main.scala:8: error: ; expected but string constant found
    ++ "world"
       ^
	at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:16)
	at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:16)
	at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
	at scala.meta.internal.parsers.Reporter.syntaxError(Reporter.scala:17)
	at scala.meta.internal.parsers.Reporter.syntaxError$(Reporter.scala:17)
	at scala.meta.internal.parsers.Reporter$$anon$1.syntaxError(Reporter.scala:22)
	at scala.meta.internal.parsers.ScalametaParser.syntaxErrorExpected(ScalametaParser.scala:941)
	at scala.meta.internal.parsers.ScalametaParser.accept(ScalametaParser.scala:947)
	at scala.meta.internal.parsers.ScalametaParser.acceptStatSep(ScalametaParser.scala:957)
	at scala.meta.internal.parsers.ScalametaParser.acceptStatSepOpt(ScalametaParser.scala:961)
	at scala.meta.internal.parsers.ScalametaParser.statSeq(ScalametaParser.scala:5060)
	at scala.meta.internal.parsers.ScalametaParser.templateStats(ScalametaParser.scala:5130)
	at scala.meta.internal.parsers.ScalametaParser.templateStatSeq(ScalametaParser.scala:5110)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$templateBody$1(ScalametaParser.scala:4945)
	at scala.meta.internal.parsers.ScalametaParser.inBraces(ScalametaParser.scala:800)
	at scala.meta.internal.parsers.ScalametaParser.templateBody(ScalametaParser.scala:4945)
	at scala.meta.internal.parsers.ScalametaParser.templateBodyOpt(ScalametaParser.scala:4953)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$templateOpt$1(ScalametaParser.scala:4938)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:888)
	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:922)
	at scala.meta.internal.parsers.ScalametaParser.templateOpt(ScalametaParser.scala:4923)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$objectDef$1(ScalametaParser.scala:4682)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:888)
	at scala.meta.internal.parsers.ScalametaParser.objectDef(ScalametaParser.scala:4674)
	at scala.meta.internal.parsers.ScalametaParser.tmplDef(ScalametaParser.scala:4558)
	at scala.meta.internal.parsers.ScalametaParser.topLevelTmplDef(ScalametaParser.scala:4540)
	at scala.meta.internal.parsers.ScalametaParser$$anonfun$topStat$1.applyOrElse(ScalametaParser.scala:5079)
	at scala.meta.internal.parsers.ScalametaParser$$anonfun$topStat$1.applyOrElse(ScalametaParser.scala:5067)
	at scala.runtime.AbstractPartialFunction.apply(AbstractPartialFunction.scala:35)
	at scala.meta.internal.parsers.ScalametaParser.statSeq(ScalametaParser.scala:5057)
	at scala.meta.internal.parsers.ScalametaParser.topStatSeq(ScalametaParser.scala:5066)
	at scala.meta.internal.parsers.ScalametaParser.bracelessPackageStats$1(ScalametaParser.scala:5289)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$batchSource$12(ScalametaParser.scala:5295)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:888)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$batchSource$1(ScalametaParser.scala:5295)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:888)
	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:922)
	at scala.meta.internal.parsers.ScalametaParser.batchSource(ScalametaParser.scala:5256)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$source$1(ScalametaParser.scala:5239)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:888)
	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:922)
	at scala.meta.internal.parsers.ScalametaParser.source(ScalametaParser.scala:5238)
	at scala.meta.internal.parsers.ScalametaParser.entrypointSource(ScalametaParser.scala:5244)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$parseSource$2(ScalametaParser.scala:143)
	at scala.meta.internal.parsers.ScalametaParser.parseRule(ScalametaParser.scala:53)
	at scala.meta.internal.parsers.ScalametaParser.parseSource(ScalametaParser.scala:143)
	at scala.meta.parsers.Parse$.$anonfun$parseSource$1(Parse.scala:29)
	at scala.meta.internal.parsers.ScalametaParser$$anon$264.apply(ScalametaParser.scala:5308)
	at scala.meta.parsers.Api$XtensionParseDialectInput.parse(Api.scala:25)
	at scala.meta.internal.semanticdb.scalac.ParseOps$XtensionCompilationUnitSource.toSource(ParseOps.scala:17)
	at scala.meta.internal.semanticdb.scalac.TextDocumentOps$XtensionCompilationUnitDocument.toTextDocument(TextDocumentOps.scala:201)
	at scala.meta.internal.semanticdb.scalac.TextDocumentOps$XtensionCompilationUnitDocument.toTextDocument(TextDocumentOps.scala:52)
	at scala.meta.internal.semanticdb.scalac.SemanticdbPipeline$SemanticdbTyperComponent$ComputeSemanticdbPhase.saveSemanticdbForCompilationUnit(SemanticdbPipeline.scala:60)
	at scala.meta.internal.semanticdb.scalac.SemanticdbPipeline$SemanticdbTyperComponent$ComputeSemanticdbPhase.apply(SemanticdbPipeline.scala:67)
	at scala.tools.nsc.Global$GlobalPhase.applyPhase(Global.scala:454)
	at scala.tools.nsc.Global$GlobalPhase.run(Global.scala:401)
	at scala.meta.internal.semanticdb.scalac.SemanticdbPipeline$SemanticdbTyperComponent$ComputeSemanticdbPhase.run(SemanticdbPipeline.scala:77)
	at scala.tools.nsc.Global$Run.compileUnitsInternal(Global.scala:1519)
	at scala.tools.nsc.Global$Run.compileUnits(Global.scala:1503)
	at scala.tools.nsc.Global$Run.compileSources(Global.scala:1495)
	at scala.tools.nsc.Global$Run.compileFiles(Global.scala:1609)
	at xsbt.CachedCompiler0.run(CompilerBridge.scala:163)
	at xsbt.CachedCompiler0.run(CompilerBridge.scala:134)
	at xsbt.CompilerBridge.run(CompilerBridge.scala:39)
	at sbt.internal.inc.AnalyzingCompiler.compile(AnalyzingCompiler.scala:91)
	at org.jetbrains.jps.incremental.scala.local.IdeaIncrementalCompiler.compile(IdeaIncrementalCompiler.scala:57)
	at org.jetbrains.jps.incremental.scala.local.LocalServer.doCompile(LocalServer.scala:52)
	at org.jetbrains.jps.incremental.scala.local.LocalServer.compile(LocalServer.scala:30)
	at org.jetbrains.jps.incremental.scala.remote.Main$.compileLogic(Main.scala:207)
	at org.jetbrains.jps.incremental.scala.remote.Main$.$anonfun$handleCommand$1(Main.scala:190)
	at org.jetbrains.jps.incremental.scala.remote.Main$.decorated$1(Main.scala:180)
	at org.jetbrains.jps.incremental.scala.remote.Main$.handleCommand(Main.scala:187)
	at org.jetbrains.jps.incremental.scala.remote.Main$.serverLogic(Main.scala:163)
	at org.jetbrains.jps.incremental.scala.remote.Main$.nailMain(Main.scala:103)
	at org.jetbrains.jps.incremental.scala.remote.Main.nailMain(Main.scala)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:77)
	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.base/java.lang.reflect.Method.invoke(Method.java:568)
	at com.martiansoftware.nailgun.NGSession.run(NGSession.java:319)
```
</details>
