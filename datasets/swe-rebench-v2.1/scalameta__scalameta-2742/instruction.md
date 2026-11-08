InvariantFailedException when attempting to extend a type
Version `4.5.4`:

```scala
trait B extends A.type
```
results in an `org.scalameta.invariants.InvariantFailedException`:
<details>

```
Exception in thread "main" org.scalameta.invariants.InvariantFailedException: invariant failed:
when verifying scala.meta.internal.trees.`package`.XtensionTreesType(tpe).isConstructable
found that scala.meta.internal.trees.`package`.XtensionTreesType(tpe).isConstructable is false
where tpe = A.type
	at org.scalameta.invariants.InvariantFailedException$.raise(Exceptions.scala:19)
	at scala.meta.Init$.internal$265(Trees.scala:494)
	at scala.meta.Init$.apply(Trees.scala:493)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$initRest$1(ScalametaParser.scala:3834)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:296)
	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:337)
	at scala.meta.internal.parsers.ScalametaParser.initRest(ScalametaParser.scala:3812)
	at scala.meta.internal.parsers.ScalametaParser.initInsideTemplate(ScalametaParser.scala:3800)
	at scala.meta.internal.parsers.ScalametaParser.init(ScalametaParser.scala:3891)
	at scala.meta.internal.parsers.ScalametaParser.templateParents(ScalametaParser.scala:3901)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$template$1(ScalametaParser.scala:3949)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:296)
	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:337)
	at scala.meta.internal.parsers.ScalametaParser.template(ScalametaParser.scala:3937)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$templateOpt$1(ScalametaParser.scala:3980)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:296)
	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:337)
	at scala.meta.internal.parsers.ScalametaParser.templateOpt(ScalametaParser.scala:3969)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$traitDef$1(ScalametaParser.scala:3617)
	at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:339)
	at scala.meta.internal.parsers.ScalametaParser.autoEndPos(ScalametaParser.scala:341)
	at scala.meta.internal.parsers.ScalametaParser.traitDef(ScalametaParser.scala:3596)
	at scala.meta.internal.parsers.ScalametaParser.tmplDef(ScalametaParser.scala:3576)
	at scala.meta.internal.parsers.ScalametaParser.topLevelTmplDef(ScalametaParser.scala:3565)
	at scala.meta.internal.parsers.ScalametaParser$$anonfun$4.applyOrElse(ScalametaParser.scala:4140)
	at scala.meta.internal.parsers.ScalametaParser$$anonfun$4.applyOrElse(ScalametaParser.scala:4128)
	at scala.PartialFunction.$anonfun$runWith$1(PartialFunction.scala:231)
	at scala.PartialFunction.$anonfun$runWith$1$adapted(PartialFunction.scala:230)
	at scala.meta.internal.parsers.ScalametaParser.statSeqBuf(ScalametaParser.scala:4121)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$batchSource$14(ScalametaParser.scala:4337)
	at scala.Option.getOrElse(Option.scala:201)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$batchSource$1(ScalametaParser.scala:4337)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:296)
	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:337)
	at scala.meta.internal.parsers.ScalametaParser.batchSource(ScalametaParser.scala:4292)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$source$1(ScalametaParser.scala:4285)
	at scala.meta.internal.parsers.ScalametaParser.atPos(ScalametaParser.scala:296)
	at scala.meta.internal.parsers.ScalametaParser.autoPos(ScalametaParser.scala:337)
	at scala.meta.internal.parsers.ScalametaParser.source(ScalametaParser.scala:4285)
	at scala.meta.internal.parsers.ScalametaParser.entrypointSource(ScalametaParser.scala:4290)
	at scala.meta.internal.parsers.ScalametaParser.parseSourceImpl(ScalametaParser.scala:132)
	at scala.meta.internal.parsers.ScalametaParser.$anonfun$parseSource$1(ScalametaParser.scala:129)
	at scala.meta.internal.parsers.ScalametaParser.parseRuleAfterBOF(ScalametaParser.scala:56)
	at scala.meta.internal.parsers.ScalametaParser.parseRule(ScalametaParser.scala:51)
	at scala.meta.internal.parsers.ScalametaParser.parseSource(ScalametaParser.scala:129)
	at scala.meta.parsers.Parse$.$anonfun$parseSource$1(Parse.scala:29)
	at scala.meta.parsers.Parse$$anon$1.apply(Parse.scala:36)
	at scala.meta.parsers.Api$XtensionParseDialectInput.parse(Api.scala:25)
	at scala.meta.parsers.Api$XtensionParseInputLike.parse(Api.scala:14)
	at a$.delayedEndpoint$a$1(a.scala:5)
	at a$delayedInit$body.apply(a.scala:1)
	at scala.Function0.apply$mcV$sp(Function0.scala:39)
	at scala.Function0.apply$mcV$sp$(Function0.scala:39)
	at scala.runtime.AbstractFunction0.apply$mcV$sp(AbstractFunction0.scala:17)
	at scala.App.$anonfun$main$1(App.scala:76)
	at scala.App.$anonfun$main$1$adapted(App.scala:76)
	at scala.collection.IterableOnceOps.foreach(IterableOnce.scala:563)
	at scala.collection.IterableOnceOps.foreach$(IterableOnce.scala:561)
	at scala.collection.AbstractIterable.foreach(Iterable.scala:926)
	at scala.App.main(App.scala:76)
	at scala.App.main$(App.scala:74)
	at a$.main(a.scala:1)
	at a.main(a.scala)
```

</details>

[Scastie](https://scastie.scala-lang.org/h0q06oYrRxiKE8mLdTNrCg)

### Additional contract requirements

- Parsing `trait B extends A.type` must fail with a parse error (a `ParseException` raised by the parser) instead of an internal invariant failure.
