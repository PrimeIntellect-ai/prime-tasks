Wrong indent in Scaladoc due to `i.e.`

## Configuration (required) ##

```
runner.dialect = "scala3"
version = "3.7.3"
maxColumn = 80
```

## Command-line parameters (required) ##

Pull request created by scala-steward https://github.com/ThoughtWorksInc/Dsl.scala/pull/660

## Steps

scala-steward created a pull request to upgrade scalafmt from 3.7.1 to 3.7.3

## Problem

Scalafmt formats code like this:
```scala
  *   Note that [[Dsl.Keyword#unary_$bang !-notation]] can be used on both
  *   `trampoline3` and `trampolineSuccess0` even when they are different types,
  * i.e. `trampoline3` is a vanilla [[scalaz.Free.Trampoline Trampoline]], while
  * `trampolineSuccess0` is a
```

## Expectation

I would like the formatted output to look like this:
```scala
  *   Note that [[Dsl.Keyword#unary_$bang !-notation]] can be used on both
  *   `trampoline3` and `trampolineSuccess0` even when they are different types,
  *   i.e. `trampoline3` is a vanilla [[scalaz.Free.Trampoline Trampoline]], while
  *   `trampolineSuccess0` is a
```

## Workaround

Use scalafmt 3.7.1

## Notes

See https://github.com/ThoughtWorksInc/Dsl.scala/pull/660/files#diff-48d17d795a0c78238baf49e1f634066cb12b49a96718615460ebc2c99fb69530R84-R115

### Additional contract requirements

The requested behavior is observable in this repository through the Scaladoc
parser, `scala.meta.internal.parsers.ScaladocParser.parse`. The requirement is
satisfied when a line beginning with `i.e.` that follows the text of a list item
is parsed as a continuation of that list item's text: the words of the `i.e.`
line (for example `i.e.` and the following word) must appear in the enclosing
`ListItem.text`, and no separate list item or paragraph may be produced for that
line. This is what preserves the indentation shown in the expected output above.
