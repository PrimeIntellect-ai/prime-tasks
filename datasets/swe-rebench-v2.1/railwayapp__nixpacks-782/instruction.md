Scala sbt support
### Feature request

Provide support for Scala sbt projects to compile to jar files that can be deployed similarly to the way maven and gradle is handled

### Motivation

I want to build docker images for my sbt application while currently only maven and gradle are supported.

### Contribution

Would love to help by sending a PR

### Additional contract requirements

A project is detected as a Scala sbt project when its root directory contains a
`build.sbt` file. For such a project the generated build plan must contain:

- a `setup` phase that installs the Nix packages `sbt` and `jdk` (in that order);
- a `build` phase that depends on the `install` and `setup` phases (in that order)
  and whose only command is `sbt stage`;
- the build phase cache directories `/root/.sbt`, `/root/.ivy2/cache` and
  `/root/.cache/coursier`;
- a start command of `./target/universal/stage/bin/main`;
- the `NIXPACKS_METADATA` variable set to `scala`.
