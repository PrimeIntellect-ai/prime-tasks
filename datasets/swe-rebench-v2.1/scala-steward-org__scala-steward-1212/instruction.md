SBT Plugin not cleaned up after run
The `StewardPlugin.scala` plugin is not cleaned up after using scala-steward. The following 2 plugin files persist.

`/jenkins/.sbt/0.13/plugins/StewardPlugin.scala` and `/jenkins/.sbt/1.0/plugins/StewardPlugin.scala`

It seems they're being created here "temporarily" but never cleaned up. https://github.com/fthomas/scala-steward/blob/f251fcdaac80f55bc0fb21017268c8a77fe70be4/modules/core/src/main/scala/org/scalasteward/core/sbt/SbtAlg.scala#L71-L79

Thank you for  👀

### Additional contract requirements

`SbtAlg.addGlobalPlugins` must create the following global sbt plugin files before running the
supplied effect `fa`, and remove all of them once `fa` has completed, leaving no plugin artefacts
behind:

- `<sbt home>/.sbt/0.13/plugins/scala-steward.sbt`
- `<sbt home>/.sbt/1.0/plugins/scala-steward.sbt`
- `<sbt home>/.sbt/0.13/plugins/StewardPlugin.scala`
- `<sbt home>/.sbt/1.0/plugins/StewardPlugin.scala`

The order in which these files are created, and the order in which they are removed, is not
specified. The only ordering guarantees are that every file exists while `fa` runs and that every
file has been removed after `fa` has completed.
