`scala-cli` dependencies: "WARN  Unable to bump version for update [...]"
Hi all! I'm facing some issues with a Scala CLI repository: my private Scala Steward runner is not updating the project's dependencies after properly recognizing they need to get bumped.

Scala Steward logs when processing:

```
  2024-06-01 22:37:57,270 INFO  Found 7 updates:
    com.softwaremill.sttp.client3:(cats, cats_3) : 3.9.6 -> 3.9.7
    com.softwaremill.sttp.client3:(cats, cats_3) : 3.9.6 -> 3.9.7
    com.softwaremill.sttp.client3:(circe, circe_3) : 3.9.6 -> 3.9.7
    com.softwaremill.sttp.client3:(circe, circe_3) : 3.9.6 -> 3.9.7
    com.softwaremill.sttp.client3:(core, core_3) : 3.9.6 -> 3.9.7
    com.softwaremill.sttp.client3:(core, core_3) : 3.9.6 -> 3.9.7
    org.scalameta:(munit, munit_3) : 0.7.29 -> 1.0.0
  2024-06-01 22:37:57,274 INFO  horothesun/my-repo is outdated:
    new version: com.softwaremill.sttp.client3:(cats, cats_3) : 3.9.6 -> 3.9.7
    new version: com.softwaremill.sttp.client3:(circe, circe_3) : 3.9.6 -> 3.9.7
    new version: com.softwaremill.sttp.client3:(core, core_3) : 3.9.6 -> 3.9.7
    new version: org.scalameta:(munit, munit_3) : 0.7.29 -> 1.0.0
  2024-06-01 22:37:57,275 INFO  Nurture horothesun/my-repo
  2024-06-01 22:37:57,282 INFO  Clone horothesun/my-repo
  2024-06-01 22:37:57,845 INFO  Found 2 updates:
    com.softwaremill.sttp.client3:{(cats, cats_3), (circe, circe_3), (core, core_3)} : 3.9.6 -> 3.9.7
    org.scalameta:(munit, munit_3) : 0.7.29 -> 1.0.0
  2024-06-01 22:37:57,862 INFO  Process update com.softwaremill.sttp.client3:{(cats, cats_3), (circe, circe_3), (core, core_3)} : 3.9.6 -> 3.9.7
  2024-06-01 22:37:58,089 WARN  Unable to bump version for update com.softwaremill.sttp.client3:{(cats, cats_3), (circe, circe_3), (core, core_3)} : 3.9.6 -> 3.9.7
  2024-06-01 22:37:58,091 WARN  No commits created
  2024-06-01 22:37:58,104 INFO  Process update org.scalameta:(munit, munit_3) : 0.7.29 -> 1.0.0
  2024-06-01 22:37:58,256 WARN  Unable to bump version for update org.scalameta:(munit, munit_3) : 0.7.29 -> 1.0.0
  2024-06-01 22:37:58,256 WARN  No commits created
```

Here're the `main.sc` dependencies section:

```scala
//> using scala "3.4.2"
//> using jvm "temurin:21"

//> using dep "org.typelevel::cats-effect:3.5.4"
//> using dep "co.fs2::fs2-core:3.10.2"
//> using dep "com.softwaremill.sttp.client3::core:3.9.6"
//> using dep "com.softwaremill.sttp.client3::cats:3.9.6"
//> using dep "com.softwaremill.sttp.client3::circe:3.9.6"
//> using dep "io.circe::circe-core:0.14.7"
//> using dep "io.circe::circe-generic:0.14.7"

//> using test.dep "org.scalameta::munit:0.7.29"
```

P.S.: the Scala version (`3.4.2`) was updated correctly by the Scala Steward runner, though.

TIA! 🙏

### Additional contract requirements

When a grouped update includes multiple Scala CLI dependencies declared with `using dep` or `using test.dep`, apply the requested version update to every matching dependency in the group while leaving unrelated file content unchanged.
