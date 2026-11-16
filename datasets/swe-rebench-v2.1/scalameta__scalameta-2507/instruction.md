Formatter errors with trait mixin, enum and extension declarations
- **Version**: 2.4.3
- **Integration**: None, reproduces in VSCode, and IntelliJ
- **Configuration**:
```
version = "3.1.1"
runner.dialect = scala3
```

## Steps

Given code like this:
```scala
trait T
trait T2 { self: T =>
  enum T2Enum:
    case EnumCase

  extension (n: Int) def negate: Int = -n
}
```

When I run scalafmt like this (in sbt console):

```bash
scalafmt
```

## Problem

Scalafmt errors saying a `;` is required, even though `compile` passes:
```scala
sbt:scalafmt-bug-reports> scalafmt
[info] Formatting 1 Scala sources...
[error] S:\programming\personal\scalafmt-bug-reports\src\main\scala\io\github\kory33\bugreports\scalafmt\Test.scala:8: error: [dialect scala3]
; expected but identifier found
[error]   extension (n: Int)
[error]   ^: S:\programming\personal\scalafmt-bug-reports\src\main\scala\io\github\kory33\bugreports\scalafmt\Test.scala
[error] (Compile / scalafmt) S:\programming\personal\scalafmt-bug-reports\src\main\scala\io\github\kory33\bugreports\scalafmt\Test.scala:8: error: [dialect scala3] ; expected but identifier found
[error]   extension (n: Int)
[error]   ^: S:\programming\personal\scalafmt-bug-reports\src\main\scala\io\github\kory33\bugreports\scalafmt\Test.scala
[error] Total time: 0 s, completed 2021/11/13 11:05:42
sbt:scalafmt-bug-reports> compile
[info] compiling 1 Scala source to S:\programming\personal\scalafmt-bug-reports\target\scala-3.1.0\classes ...
[success] Total time: 4 s, completed 2021/11/13 11:06:28
```

## Expectation

I would like the formatter to format the code in some way without outputting an error.

## Workaround

I've found that by bringing `enum` declaration below `extension` the formatter works as expected.

```Scala
trait T
trait T2 { self: T =>
  extension (n: Int) def negate: Int = -n

  enum T2Enum:
    case EnumCase
}
```

## Notes

The example is minimized. Removing any one of trait mixin, extension or enum solves the issue. Please see https://github.com/kory33/scalafmt-bug-reports/tree/072c26b778a2baf10f8af1bf43ab9605e084c8b2 for the full project example.

### Additional contract requirements

- For a trait body containing an enum followed by an extension declaration, format it with this exact layout:
```scala
trait T2 { self: T =>
  enum T2Enum { case EnumCase }
  extension (n: Int) def negate: Int = -n
}
```
