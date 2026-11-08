Scala 3: `transparent class` fails to parse
## Configuration ##

```
version = 3.8.3
runner.dialect = scala3
```

## Command-line parameters (required) ##

When I run scalafmt via CLI like this: `scalafmt a.scala`

## Steps

Given code like this:
```scala
transparent class Foo
```

## Problem

Scalafmt fails to parse the code:
```scala
/tmp/test/a.scala:1: error: [dialect scala3] `;` expected but `class` found
transparent class Foo
            ^
```

## Expectation

Scalafmt does not fail to parse the code

## Workaround

disabling formatting for the line

## Notes

> Scala 3 allows one to mark a trait or class as `transparent`

https://docs.scala-lang.org/scala3/reference/other-new-features/transparent-traits.html
