"Unable to bump version" when version is defined as both a string and a val
The great work in #2816 resolved most of the "Unable to bump version" errors that I've seen on internal projects. However, I did find one new one.

The build setup looks like this:

```scala
val FooLibrariesVersion = "1.2.3"

libraryDependencies ++= Seq(
 "com.foo" %% "library-1" % FooLibrariesVersion,
 "com.foo" %% "library-2" % FooLibrariesVersion,
 "com.foo" %% "library-3" % FooLibrariesVersion,
 "com.foo" %% "library-4" % "0.1.2"
)
```

The latest version of all four dependencies is "2.0.0".

Here's what scala-steward does:

1. recognizes that `"library-1", "library-2", "library-3", "library-4"` all need to be bumped to `"2.0.0"` as well ("Found 4 updates")
2. fails to bump `"library-1", "library-2", "library-3"` ("Unable to bump version")
3. correctly bumps `"library-4"` to `"2.0.0"`


I've changed the library names and versions, but everything should still map to reality.

I suspect that consolidating the versions to a single val will fix things, but this still seems like it's worth reporting.

Can someone point me to a way to test out this specific scenario w/ the current heuristics implementation? Maybe I can take a pass at fixing this.
