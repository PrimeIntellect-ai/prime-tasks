Prevent updates from RC to NIGHTLY version
See https://github.com/stryker-mutator/stryker4s/pull/612. I think this can be achieved by [HIDDEN] [match](https://github.com/scala-steward-org/scala-steward/blob/41eb40b2fbc11ddd3e6e1548e038ae919defa259/modules/core/src/main/scala/org/scalasteward/core/data/Version.scala#L128-L135).

### Additional contract requirements

- When the current version is an RC (release candidate), do not select a NIGHTLY version as its update.
