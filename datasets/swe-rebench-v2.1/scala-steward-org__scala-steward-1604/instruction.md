Scala steward updated an unrelated plugin as well as the intended dependency
As the title says scala-steward tried to update a plugin as well as the intended dependency, they both happened to be on the same version (`2.4.0`).

The intended dependencies were `jsoniter-scala-core` and `jsoniter-scala-macros` from `2.4.0` to `2.4.1` (controlled by a single value), but it also updated the `sbt-scalafmt` plugin to `2.4.1` in the process.

You can see the PR here: https://github.com/permutive/fs2-google-pubsub/pull/123
