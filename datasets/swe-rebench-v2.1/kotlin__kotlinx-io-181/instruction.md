Use Gradle versions catalog to manage dependencies
Currently, dependency versions are specified ad hoc, which may lead to incorrect/inconsistent versions among different modules (see
Having all dependencies and their versions specified in a single place would be nice, and Gradle version catalogs provide such functionality.

### Additional contract requirements

- Define plugin aliases `kover` and `dokka` in the version catalog so they are available as `libs.plugins.kover` and `libs.plugins.dokka`.
