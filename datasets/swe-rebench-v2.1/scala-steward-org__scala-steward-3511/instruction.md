My Scala Steward app is breaking on a Mill repo
I'm using https://github.com/nafg/nafg-scala-steward (based on https://github.com/armanbilge/diy-steward) for some of my repos and for the last few weeks it's been failing. The error is:

```
  2024-11-19 04:16:07,625 INFO  ──────────── Steward nafg/scala-grist ────────────
  2024-11-19 04:16:07,625 INFO  Check cache of nafg/scala-grist
  2024-11-19 04:16:08,008 INFO  Clone nafg/scala-grist
  2024-11-19 04:16:08,280 INFO  Refresh cache of nafg/scala-grist
  2024-11-19 04:16:08,354 INFO  Get dependencies in . from Mill
  2024-11-19 04:16:24,430 ERROR Steward nafg/scala-grist failed
  org.scalasteward.core.buildtool.mill.parser$CirceParseError: Failed to decode Modules
      at org.scalasteward.core.buildtool.mill.parser$.$anonfun$parseModules$1(parser.scala:43)
      at cats.syntax.EitherOps$.leftMap$extension(either.scala:193)
      at org.scalasteward.core.buildtool.mill.parser$.parseModules(parser.scala:43)
      at org.scalasteward.core.buildtool.mill.MillAlg.$anonfun$getProjectDependencies$1(MillAlg.scala:85)
      at map @ org.scalasteward.core.buildtool.mill.MillAlg.$anonfun$getProjectDependencies$1(MillAlg.scala:84)
      at map @ org.scalasteward.core.buildtool.mill.MillAlg.$anonfun$getProjectDependencies$1(MillAlg.scala:84)
      at main$ @ org.scalasteward.core.Main$.main(Main.scala:23)
      at timeoutAndForget @ org.scalasteward.core.io.process$.$anonfun$slurp$3(process.scala:85)
      at adaptErr$extension @ org.scalasteward.core.update.artifact.ArtifactMigrationsLoader.decodeMigrations(ArtifactMigrationsLoader.scala:50)
      at delay @ org.scalasteward.core.io.process$.$anonfun$slurp$1(process.scala:63)
  Caused by: io.circe.ParsingFailure: expected whitespace or eof got '..' (line 95, column 1)
  2024-11-19 04:16:24,432 INFO  ──────────── Total time: Steward nafg/scala-grist: 16s 807ms ────────────
```

However if I try to simulate it locally, not only does the output not explain the error, there is no line 95:

```
❯ mill --no-server --disable-ticker --import "ivy:org.scala-steward::scala-steward-mill-plugin::0.18.0" show org.scalasteward.mill.plugin.StewardPlugin/extractDeps | cat -n
[build.mill] [info] compiling 1 Scala source to /home/naftoli/repositories/github.com/nafg/scala-grist/out/mill-build/compile.dest/classes ...
[build.mill] [info] done compiling
     1	{
     2	  "modules": [
     3	    {
     4	      "name": "core[3.4.2]",
     5	      "repositories": [
     6	        {
     7	          "url": "https://repo1.maven.org/maven2",
     8	          "type": "maven",
     9	          "auth": null,
    10	          "headers": null
    11	        }
    12	      ],
    13	      "dependencies": [
    14	        {
    15	          "groupId": "io.circe",
    16	          "artifactId": {
    17	            "name": "circe-parser",
    18	            "maybeCrossName": "circe-parser_3"
    19	          },
    20	          "version": "0.14.10"
    21	        },
    22	        {
    23	          "groupId": "io.circe",
    24	          "artifactId": {
    25	            "name": "circe-generic",
    26	            "maybeCrossName": "circe-generic_3"
    27	          },
    28	          "version": "0.14.10"
    29	        },
    30	        {
    31	          "groupId": "dev.zio",
    32	          "artifactId": {
    33	            "name": "zio-http",
    34	            "maybeCrossName": "zio-http_3"
    35	          },
    36	          "version": "3.0.1"
    37	        },
    38	        {
    39	          "groupId": "org.scala-lang",
    40	          "artifactId": {
    41	            "name": "scala3-library",
    42	            "maybeCrossName": "scala3-library_3"
    43	          },
    44	          "version": "3.4.2"
    45	        }
    46	      ]
    47	    },
    48	    {
    49	      "name": "core[2.13.14]",
    50	      "repositories": [
    51	        {
    52	          "url": "https://repo1.maven.org/maven2",
    53	          "type": "maven",
    54	          "auth": null,
    55	          "headers": null
    56	        }
    57	      ],
    58	      "dependencies": [
    59	        {
    60	          "groupId": "io.circe",
    61	          "artifactId": {
    62	            "name": "circe-parser",
    63	            "maybeCrossName": "circe-parser_2.13"
    64	          },
    65	          "version": "0.14.10"
    66	        },
    67	        {
    68	          "groupId": "io.circe",
    69	          "artifactId": {
    70	            "name": "circe-generic",
    71	            "maybeCrossName": "circe-generic_2.13"
    72	          },
    73	          "version": "0.14.10"
    74	        },
    75	        {
    76	          "groupId": "dev.zio",
    77	          "artifactId": {
    78	            "name": "zio-http",
    79	            "maybeCrossName": "zio-http_2.13"
    80	          },
    81	          "version": "3.0.1"
    82	        },
    83	        {
    84	          "groupId": "org.scala-lang",
    85	          "artifactId": {
    86	            "name": "scala-library",
    87	            "maybeCrossName": null
    88	          },
    89	          "version": "2.13.14"
    90	        }
    91	      ]
    92	    }
    93	  ]
    94	}
```
