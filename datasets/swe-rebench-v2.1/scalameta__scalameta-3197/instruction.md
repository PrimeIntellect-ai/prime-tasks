Support erased definitions
This template is mostly a guideline, not a strict requirement, except
the sections marked `(required)`.

Please make sure that the issue is observable using the latest version of `scalafmt` and
within the `scalafmt` **CLI**: `https://scalameta.org/scalafmt/docs/installation.html#cli`

Using the CLI is _mandatory_, in one of these configurations:
- latest version of CLI and latest version in `.scalafmt.conf`
- previous version of CLI and latest version in `.scalafmt.conf`
- latest version of CLI and previous version in `.scalafmt.conf`

## Configuration (required) ##

Please paste the contents of your `.scalafmt.conf` file here:
```
version = 3.5.8
binPack.parentConstructors = true
maxColumn = 120
includeCurlyBraceInSelectChains = true
align.preset = most
trailingCommas = preserve
runner.dialect = scala3
project.excludeFilters = ["kaivessel/package.scala"]

rewrite.scala3.insertEndMarkerMinLines = 5
...
```

NB: before submitting, please confirm that the problem is observed in the
*latest published* version of the formatter! We don't publish hotfixes for older
versions, and the problem you have observed in an older version may have already
been fixed.

## Command-line parameters (required) ##

When I run scalafmt via CLI like this: `<command-line parameter>`

If you were not using CLI initially:
- please check using `scalafmt` CLI before submitting here (required)
- if the problem does not present via CLI, DO NOT SUBMIT
  here: this is NOT a formatter issue
  - it could be an issue with your integration (sbt-scalafmt, metals, intellij etc.)
  - instead please submit the issue in the appropriate tool's repository
  - for instance, if the tool is `sbt` with the `sbt-scalafmt` plugin: please
    submit in `sbt-scalafmt` and include scalafmt parameters from `build.sbt`
    and the `sbt` command used
  - conversely, do not submit formatting issues into other tools; you must first
    verify using `scalafmt` CLI

## Steps

Given code like this:
```scala
package kuraga.datum

import scala.language.experimental.erasedDefinitions

import Repr.Holder

object Repr:
  trait Holder:
    type A

trait Repr[-P[-_, +_], +X]:
  def apply(erased holder: Holder)(p: P[X, holder.A]): holder.A
```

## Problem

Scalafmt formats raises an error like this:
```scala
Repr.scala:12: error: [dialect scala3] : expected but identifier found
  def apply(erased holder: Holder)(p: P[X, holder.A]): holder.A
```


## Workaround

I've found that by...

## Notes

See also...

### Additional contract requirements

- An `erased` modifier on a function-type argument is accepted and represented on that argument as `Mod.Erased()`.
- An `erased` modifier on a dependent-type parameter is accepted and represented on that parameter as `Mod.Erased()`.
- Printing function types and dependent function types with erased arguments or parameters preserves the `erased` modifier.
- The reported Scala 3 method signature with an erased method parameter parses without the reported error.
