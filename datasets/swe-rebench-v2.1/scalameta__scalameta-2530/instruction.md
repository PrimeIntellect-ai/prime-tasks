Secondary constructors in trait lead to invariant failed in worksheet mode
I copied the code form the [Auxiliary Class Constructors article](https://docs.scala-lang.org/overviews/scala-book/classes-aux-constructors.html), pasted into Scastie, changed `class` to `trait` and set the Scala version to 3.1.0.

## Compiler version

at least 3.0.0, 3.1.0 and 3.1.1-RC1

## Minimized code

```Scala
trait P:
 def this(x: Unit) = this()
```

## Output (click arrow to expand)
<details>
org.scalameta.invariants.InvariantFailedException: invariant failed:
when verifying scala.meta.classifiers.`package`.XtensionClassifiable[scala.meta.Template](templ)(scala.meta.Tree.classifiable[scala.meta.Template]).is[Template.Quasi](Template.this.Quasi.ClassifierClass[scala.meta.Template]).||(templ.stats.forall(((x$9: scala.meta.Stat) => scala.meta.classifiers.`package`.XtensionClassifiable[scala.meta.Stat](x$9)(scala.meta.Tree.classifiable[scala.meta.Stat]).is[Ctor](scala.meta.Ctor.ClassifierClass[scala.meta.Stat]).`unary_!`)))
found that scala.meta.classifiers.`package`.XtensionClassifiable[scala.meta.Template](templ)(scala.meta.Tree.classifiable[scala.meta.Template]).is[Template.Quasi](Template.this.Quasi.ClassifierClass[scala.meta.Template]) is false
and also templ.stats.forall(((x$9: scala.meta.Stat) => scala.meta.classifiers.`package`.XtensionClassifiable[scala.meta.Stat](x$9)(scala.meta.Tree.classifiable[scala.meta.Stat]).is[Ctor](scala.meta.Ctor.ClassifierClass[scala.meta.Stat]).`unary_!`)) is false
where Template = scala.meta.Template$@7998a3ca
where templ = :
 def this(x: Unit) = this()
	at org.scalameta.invariants.InvariantFailedException$.raise(Exceptions.scala:19)
	at scala.meta.Defn$Trait$.internal$247(Trees.scala:432)
	at scala.meta.Defn$Trait$.apply(Trees.scala:425)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$traitDef$1(ScalametaParser.scala:4592)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:888)
	at scala.meta.internal.parsers.ScalametaParser.traitDef(ScalametaParser.scala:4570)
	at scala.meta.internal.parsers.ScalametaParser.tmplDef(ScalametaParser.scala:4548)
	at scala.meta.internal.parsers.ScalametaParser.defOrDclOrSecondaryCtor(ScalametaParser.scala:4201)
	at scala.meta.internal.parsers.ScalametaParser.nonLocalDefOrDcl(ScalametaParser.scala:4172)
	at scala.meta.internal.parsers.ScalametaParser$$anonfun$templateStat$1$1.applyOrElse(ScalametaParser.scala:5120)
	at scala.meta.internal.parsers.ScalametaParser$$anonfun$templateStat$1$1.applyOrElse(ScalametaParser.scala:5114)
	at scala.runtime.AbstractPartialFunction.apply(AbstractPartialFunction.scala:35)
	at scala.meta.internal.parsers.ScalametaParser.statSeq(ScalametaParser.scala:5057)
	at scala.meta.internal.parsers.ScalametaParser.templateStats(ScalametaParser.scala:5130)
	at scala.meta.internal.parsers.ScalametaParser.templateStatSeq(ScalametaParser.scala:5110)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$templateBody$1(ScalametaParser.scala:4945)
	at scala.meta.internal.parsers.ScalametaParser.inBraces(ScalametaParser.scala:800)
	at scala.meta.internal.parsers.ScalametaParser.templateBody(ScalametaParser.scala:4945)
	at scala.meta.internal.parsers.ScalametaParser.templateBodyOpt(ScalametaParser.scala:4953)
	at scala.meta.internal.parsers.ScalametaParser.template(ScalametaParser.scala:4887)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$template$1(ScalametaParser.scala:4906)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:888)
	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:922)
	at scala.meta.internal.parsers.ScalametaParser.template(ScalametaParser.scala:4891)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$templateOpt$1(ScalametaParser.scala:4931)
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
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$batchSource$1(ScalametaParser.scala:5297)
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
	at scala.meta.parsers.Api$XtensionParseInputLike.parse(Api.scala:14)
	at com.olegych.scastie.instrumentation.Instrument$.apply(Instrument.scala:199)
	at com.olegych.scastie.instrumentation.InstrumentedInputs$.apply(InstrumentedInputs.scala:23)
	at com.olegych.scastie.sbt.SbtProcess$$anonfun$4.applyOrElse(SbtProcess.scala:191)
	at com.olegych.scastie.sbt.SbtProcess$$anonfun$4.applyOrElse(SbtProcess.scala:177)
	at scala.runtime.AbstractPartialFunction.apply(AbstractPartialFunction.scala:35)
	at akka.actor.FSM.processEvent(FSM.scala:707)
	at akka.actor.FSM.processEvent$(FSM.scala:704)
	at com.olegych.scastie.sbt.SbtProcess.processEvent(SbtProcess.scala:64)
	at akka.actor.FSM.akka$actor$FSM$$processMsg(FSM.scala:701)
	at akka.actor.FSM$$anonfun$receive$1.applyOrElse(FSM.scala:695)
	at akka.actor.Actor.aroundReceive(Actor.scala:539)
	at akka.actor.Actor.aroundReceive$(Actor.scala:537)
	at com.olegych.scastie.sbt.SbtProcess.aroundReceive(SbtProcess.scala:64)
	at akka.actor.ActorCell.receiveMessage(ActorCell.scala:614)
	at akka.actor.ActorCell.invoke(ActorCell.scala:583)
	at akka.dispatch.Mailbox.processMailbox(Mailbox.scala:268)
	at akka.dispatch.Mailbox.run(Mailbox.scala:229)
	at akka.dispatch.Mailbox.exec(Mailbox.scala:241)
	at akka.dispatch.forkjoin.ForkJoinTask.doExec(ForkJoinTask.java:260)
	at akka.dispatch.forkjoin.ForkJoinPool$WorkQueue.runTask(ForkJoinPool.java:1339)
	at akka.dispatch.forkjoin.ForkJoinPool.runWorker(ForkJoinPool.java:1979)
	at akka.dispatch.forkjoin.ForkJoinWorkerThread.run(ForkJoinWorkerThread.java:107)
</details>

Related:

- my [Can traits have secondary constructors in Scala 3?](https://stackoverflow.com/questions/70518466/can-traits-have-secondary-constructors-in-scala-3) Stack Overflow question
- [Dotty bug #14184](https://github.com/lampepfl/dotty/issues/14184), closed with indication that it's a Scalameta bug

### Additional contract requirements

- Secondary constructors (`def this(...)`) are accepted inside class templates.
- Secondary constructors are accepted inside enum templates.
- Secondary constructors inside trait templates are rejected with a syntax error whose message contains "Illegal secondary constructor".
- Secondary constructors inside object templates are rejected with a syntax error whose message contains "Illegal secondary constructor".
