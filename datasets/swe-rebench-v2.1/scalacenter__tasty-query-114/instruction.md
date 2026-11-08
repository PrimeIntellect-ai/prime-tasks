cannot find member StringBuilder/T in symbol[package scala.collection.mutable]
On the current main branch, this test fails

```scala
test("scala.collection") {
    given Context = Contexts.init(testClasspath)

    val scala = resolve(RootPkg / name"scala").asClass
    scala.declarations

    val StringBuilder = resolve(RootPkg / name"scala" / name"collection" / name"mutable" / tname"StringBuilder").asClass
  }
```

If I remove the `scala.declarations` line then the test passes.
