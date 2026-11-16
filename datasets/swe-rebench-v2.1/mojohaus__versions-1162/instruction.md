Null logged in "Processing change of null:<artifactId>:<old version> -> <new version>"
Setting the version (e.g. `mvn versions:set -DnewVersion=1.1.0-SNAPSHOT`) in the root dir of a multi module maven project, where the `groupId` is inherited from a parent pom, the `groupId` is logged as `null` in: `Processing change of null:my-artifact-id:1.0.0-SNAPSHOT -> 1.1.0-SNAPSHOT`. It seems only an issue with the log output, as the version of any submodule is changed as expected. The issue was introduced with version 2.16.0 of the plugin.

maven 3.9.9
versions-maven-plugin: 2.17.1
