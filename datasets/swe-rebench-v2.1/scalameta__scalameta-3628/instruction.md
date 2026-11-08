Properly formatted code using zio method `*>` is formatted so the code is no longer valid
## Configuration (required) ##

```
version = "3.8.0"

runner.dialect = scala3

fileOverride {
  "glob:**/project/*" {
    runner.dialect = scala213
  }
  "glob:**/jooq-generated/src/test/scala/**" {
    runner.dialect = scala213
  }
}

maxColumn = 150
lineEndings = unix
indent.defnSite = 2
assumeStandardLibraryStripMargin = true
align.stripMargin = true
newlines.beforeCurlyLambdaParams = multilineWithCaseOnly
rewrite.scala3.removeOptionalBraces = true
rewrite.rules = [AvoidInfix]
rewrite.neverInfix.excludeFilters = [
  until,
  to,
  by,
  eq,
  ne,
  "should.*",
  "contain.*",
  "must.*",
  in,
  ignore,
  be,
  taggedAs,
  thrownBy,
  synchronized,
  have,
  when,
  size,
  only,
  noneOf,
  oneElementOf,
  noElementsOf,
  atLeastOneElementOf,
  atMostOneElementOf,
  allElementsOf,
  inOrderElementsOf,
  theSameElementsAs,
  theSameElementsInOrderAs,
  at,
  inSet,
  ilike,
  between,
  ifNull
]

# excludes any generated code (e.g., jOOQ) from formatting
project.excludePaths = [
  "glob:**/src/**/generated/**"
]

onTestFailure = "To fix this, run 'sbt fix' from the project root directory."

```


## Command-line parameters (required) ##

When I run scalafmt via CLI like this: `scalafmt -c ./.scalafmt.conf Test.scala`


## Steps

Given code like this:
```scala
import zio.*

object Test:
  ZIO
    .succeed(42)
    .map: i =>
      i + 1
    *> ZIO.succeed(666)
```

## Problem

Scalafmt formats code like this:
```scala
import zio.*

object Test:
  ZIO
    .succeed(42)
    .map: i =>
      i + 1
        *> ZIO.succeed(666)
```

## Expectation

I would like the formatted output to look like this:
```scala
import zio.*

object Test:
  ZIO
    .succeed(42)
    .map: i =>
      i + 1
    *> ZIO.succeed(666)
```

### Additional contract requirements

The observable behaviour in this repository is the syntax tree produced by the
parser and its reprint. Parsing the example above must produce a tree in which
the `*>` infix application is applied to the result of the `.map(...)` call: the
`*>` term is a sibling of the `.map` selection, not a child of the lambda body.
The reprint of that tree must keep `*>` at the same indentation as `.map`,
outside the lambda body.
