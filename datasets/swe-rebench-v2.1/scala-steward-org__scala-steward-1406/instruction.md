Look for corresponding changes in things like '.md' files
I don't know how common this use case is, but I have some dependencies that also appear in my markdown docs, for example:

```
how to install:

```scala
resolvers += "manyangled" at "https://dl.bintray.com/manyangled/maven/"

libraryDependencies ++= Seq(
  // basic coulomb dependencies
  "com.manyangled" %% "coulomb" % "0.3.6",
  "org.typelevel" %% "spire" % "0.17.0-M1",
  "eu.timepit" %% "singleton-ops" % "0.4.0",
  // pureconfig integration:
  "com.manyangled" %% "coulomb-pureconfig" % "0.3.5",
  "com.github.pureconfig" %% "pureconfig" % "0.12.0"
)
```

Using the example above, if scala steward updated the pureconfig dep in my sbt build, in theory it also might update it in my markdown.

### Additional contract requirements

- A dependency update can also update a matching dependency declaration in a Markdown document (a file with the `.md` extension), such as a `libraryDependencies` line inside a code block.
- `EditAlg.applyUpdate` takes the set of file extensions to search as a third argument of type `Set[String]`, for example `Set(".md")`. Only files whose names end with one of the given extensions are considered for the update.
- Updates to files with the existing source extensions (`.scala`, `.sbt`, `.sbt.shared`, `.sc`, `.yml`) keep working as before when those extensions are passed.
