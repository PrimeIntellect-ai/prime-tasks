Crashes on some simple signature
Since `0.1.0` I have some crashes on some simple signatures:

Here is the test that fails:
```scala
package simple_trees

case class A(x: String)
```

```scala
  testWithContext("problem") {
    val A = resolve(name"simple_trees" / tname"A").asClass
    A.getDecl(name"copy").get.asTerm.signedName
  }
```

And the stack trace is:

```
==> X tastyquery.TypeSuite.problem  0.876s tastyquery.Exceptions$MemberNotFoundException: cannot find package member _root_ of symbol[package <root>]
    at tastyquery.Contexts$Context.$anonfun$1(Contexts.scala:124)
    at scala.Option.getOrElse(Option.scala:201)
    at tastyquery.Contexts$Context.rec$1(Contexts.scala:125)
    at tastyquery.Contexts$Context.findPackageFromRoot(Contexts.scala:129)
    at tastyquery.Types$PackageRef.symbol(Types.scala:819)
    at tastyquery.Types$NamedType$.possibleSelFromPackage(Types.scala:724)
    at tastyquery.TypeTrees$TermRefTypeTree.calculateType(TypeTrees.scala:90)
    at tastyquery.TypeTrees$TypeTree.toType(TypeTrees.scala:21)
    at tastyquery.TypeTrees$SelectTypeTree.calculateType(TypeTrees.scala:82)
    at tastyquery.TypeTrees$TypeTree.toType(TypeTrees.scala:21)
    at tastyquery.reader.tasties.TreeUnpickler.readTemplate$$anonfun$4$$anonfun$1(TreeUnpickler.scala:526)
    at scala.collection.immutable.List.map(List.scala:250)
    at tastyquery.reader.tasties.TreeUnpickler.readTemplate$$anonfun$3(TreeUnpickler.scala:527)
    at tastyquery.Symbols$ClassSymbol.parents(Symbols.scala:507)
    at tastyquery.Symbols$ClassSymbol.isDerivedValueClass(Symbols.scala:446)
    at tastyquery.Types$ErasedTypeRef$.finishErase(Types.scala:147)
    at tastyquery.Types$ErasedTypeRef$.erase(Types.scala:69)
    at tastyquery.Signatures$Signature$.rec$1(Signatures.scala:39)
    at tastyquery.Signatures$Signature$.fromMethodic(Signatures.scala:44)
    at tastyquery.Symbols$TermSymbol.signature(Symbols.scala:218)
    at tastyquery.Symbols$TermSymbol.signedName(Symbols.scala:225)
    at tastyquery.TypeSuite.$init$$$anonfun$1(TypeSuite.scala:783)
    at tastyquery.UnrestrictedUnpicklingSuite.testWithContext$$anonfun$1(UnrestrictedUnpicklingSuite.scala:9)
    at tastyquery.UnrestrictedUnpicklingSuite.testWithContext$$anonfun$3$$anonfun$1(UnrestrictedUnpicklingSuite.scala:15)
    at scala.concurrent.impl.Promise$Transformation.run(Promise.scala:431)
    at java.util.concurrent.ForkJoinTask$RunnableExecuteAction.exec(ForkJoinTask.java:1402)
    at java.util.concurrent.ForkJoinTask.doExec(ForkJoinTask.java:289)
    at java.util.concurrent.ForkJoinPool$WorkQueue.runTask(ForkJoinPool.java:1056)
    at java.util.concurrent.ForkJoinPool.runWorker(ForkJoinPool.java:1692)
    at java.util.concurrent.ForkJoinWorkerThread.run(ForkJoinWorkerThread.java:175)
```

I hope you can fix this soon and release `0.1.1` :pray:
