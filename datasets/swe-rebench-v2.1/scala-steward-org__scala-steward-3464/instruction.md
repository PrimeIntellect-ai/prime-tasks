Errors while running on a Mill project
this looks like an issues with some older Mill bootstrap scripts (which fail to correctly parse the `--import` arg). I'm not sure if Scala Steward is still bundling https://github.com/lefou/millw, but updating to the latest version could already fix the issue.

The project is: https://github.com/com-lihaoyi/mill
The Mill version used is: `0.12.1`

The full output (https://github.com/com-lihaoyi/mill/actions/runs/11672731224/job/32501971856):

```
  Error: SLF4J(I): Connected with provider of type [ch.qos.logback.classic.spi.LogbackServiceProvider]
  2024-11-04 21:10:54,778 INFO
    ____            _         ____  _                             _
   / ___|  ___ __ _| | __ _  / ___|| |_ _____      ____ _ _ __ __| |
   \___ \ / __/ _` | |/ _` | \___ \| __/ _ \ \ /\ / / _` | '__/ _` |
    ___) | (_| (_| | | (_| |  ___) | ||  __/\ V  V / (_| | | | (_| |
   |____/ \___\__,_|_|\__,_| |____/ \__\___| \_/\_/ \__,_|_|  \__,_|
   v0.31.0

  2024-11-04 21:10:55,539 INFO  Loaded 295 artifact migration(s)
  2024-11-04 21:10:55,702 INFO  Loaded 35 Scalafix migration(s)
  2024-11-04 21:10:55,842 INFO  Loaded 1 repo config(s)
  2024-11-04 21:10:56,098 INFO  Run self checks
  2024-11-04 21:10:56,253 INFO  Using git version 2.47.0
  2024-11-04 21:10:56,782 INFO  Using scalafix 0.13.0
  2024-11-04 21:10:57,337 INFO  Using scalafmt 3.8.4-RC1
  2024-11-04 21:10:58,017 INFO  Removing any run-specific files
  2024-11-04 21:10:58,029 INFO  ──────────── Steward com-lihaoyi/mill ────────────
  2024-11-04 21:10:58,031 INFO  Check cache of com-lihaoyi/mill
  2024-11-04 21:10:58,536 INFO  Clone com-lihaoyi/mill
  2024-11-04 21:12:00,531 INFO  Refresh cache of com-lihaoyi/mill
  2024-11-04 21:12:00,995 INFO  Get dependencies in . from Mill
  2024-11-04 21:12:03,176 ERROR Steward com-lihaoyi/mill failed
  org.scalasteward.core.io.process$ProcessFailedException: '"SBT_OPTS=-Xmx2048m -Xss8m -XX:MaxMetaspaceSize=512m" mill -i --import ivy:org.scala-steward::scala-steward-mill-plugin::0.18.0 show org.scalasteward.mill.plugin.StewardPlugin/extractDeps' exited with code 1.
    % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                   Dload  Upload   Total   Spent    Left  Speed
    0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
    0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
    0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
  100 64.6M  100 64.6M    0     0   122M      0 --:--:-- --:--:-- --:--:--  122M
  -i/--interactive/--no-server/--bsp must be passed in as the first argument
  	at org.scalasteward.core.io.process$.$anonfun$slurp$7(process.scala:78)
  	at org.scalasteward.core.io.process$.$anonfun$slurp$7$adapted(process.scala:72)
  	at flatMap @ org.scalasteward.core.io.process$.$anonfun$slurp$5(process.scala:72)
  	at flatMap @ fs2.Compiler$Target.flatMap(Compiler.scala:163)
  	at flatMap @ fs2.Compiler$Target.flatMap(Compiler.scala:163)
  	at flatMap @ fs2.Compiler$Target.flatMap(Compiler.scala:163)
  	at flatMap @ fs2.Compiler$Target.flatMap(Compiler.scala:163)
  	at flatMap @ fs2.Compiler$Target.flatMap(Compiler.scala:163)
  	at flatMap @ fs2.Compiler$Target.flatMap(Compiler.scala:163)
  	at modify @ fs2.internal.Scope.close(Scope.scala:262)
  	at flatMap @ fs2.Compiler$Target.flatMap(Compiler.scala:163)
  	at rethrow$extension @ fs2.Compiler$Target.$anonfun$compile$1(Compiler.scala:157)
  	at get @ fs2.internal.Scope.openScope(Scope.scala:275)
  	at flatMap @ fs2.Compiler$Target.flatMap(Compiler.scala:163)
  	at flatMap @ fs2.Pull$.$anonfun$compile$21(Pull.scala:1214)
  	at update @ fs2.internal.Scope.releaseChildScope(Scope.scala:224)
  2024-11-04 21:12:03,178 INFO  ──────────── Total time: Steward com-lihaoyi/mill: 1m 5s 149ms ────────────
  2024-11-04 21:12:03,184 INFO  ──────────── Total time: run: 1m 7s 87ms ────────────
```
