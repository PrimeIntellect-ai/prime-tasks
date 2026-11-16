Order[Version] is not transitive
One build of https://github.com/scala-steward-org/scala-steward/pull/1614 failed with:
```
failing seed for order.transitivity is jrEI318o6GIPatr-KDWf_A1_sf9ndnP7IRRq2mNh1ZD=
[info] - Order[Version].order.transitivity *** FAILED ***
[info]   GeneratorDrivenPropertyCheckFailedException was thrown during property evaluation.
[info]    (VersionTest.scala:18)
[info]     Falsified after 1 successful property evaluations.
[info]     Location: (VersionTest.scala:18)
[info]     Occurred when passed generated values (
[info]       arg0 = Version(),
[info]       arg1 = Version(0),
[info]       arg2 = Version(D+)
[info]     )
[info]     Label of failing property:
[info]       Expected: true
[info]   Received: false
```
I assume the build will succeed once it is restarted.

### Additional contract requirements

- The ordering must also match Coursier for the pair `Version("1.0e")` and `Version("1.0.0-SNAP8")`: `Version("1.0e")` must be ordered before `Version("1.0.0-SNAP8")`.
