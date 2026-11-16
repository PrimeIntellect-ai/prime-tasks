Fallback to `.github/.scala-steward.conf` if config not found in root
I think it's a good idea to fall back to the `.github` directory when loading the config.
It's getting more and more a convention to put things GitHub related in that folder. E.g. see our repo: https://github.com/playframework/playframework/tree/main/.github
~We will also move the `.mergify.yml` from the root to `.github` soon, so `.scala-steward.conf` is the last one missing.~ Done!

The change needs to be done in
* https://github.com/scala-steward-org/scala-steward/blob/main/modules/core/src/main/scala/org/scalasteward/core/repoconfig/RepoConfigAlg.scala
* maybe here too (?): https://github.com/scala-steward-org/scala-steward/blob/main/modules/core/src/main/scala/org/scalasteward/core/repoconfig/RepoConfigLoader.scala
* Update docs: https://github.com/scala-steward-org/scala-steward/blob/main/docs/repo-specific-configuration.md (maybe there is more, not sure)
