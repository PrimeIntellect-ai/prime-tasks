Prevent updates from "normal" versions to hashes
See #2359 and https://github.com/scalameta/metals-gitpod-sample/pull/85 for example.

bloop-config and sbt-bloop are example artifacts that have a few hash versions:
* https://repo1.maven.org/maven2/ch/epfl/scala/bloop-config_2.12/
* https://repo1.maven.org/maven2/ch/epfl/scala/sbt-bloop_2.12_1.0/

### Additional contract requirements

For selecting an update, a normal version has no commit-hash identifier. A hash version is either a bare string of at least eight hexadecimal characters or a release version with a hexadecimal identifier of at least six characters appended after `-` or `+` (an optional `g` may precede the identifier). Date-like identifiers are not commit hashes. For example, `1032048a` and `1.2.0+17-7ef98061` are hash versions. A normal version must not select a hash version as its next update. This restriction does not prescribe which update may be selected when the current version is itself hash-like.
