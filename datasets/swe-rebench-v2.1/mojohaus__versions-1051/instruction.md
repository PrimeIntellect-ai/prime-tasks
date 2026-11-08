versions:set does behave wrong when parent version is the same as the version to be set
Hi,

I figured out a strange behaviour of the versions plugin (tested with latest release version 2.16.2).

When I try to set the version in the following way for a project where the current version is 2024.1.0-SNAPSHOT:

`mvn -DgenerateBackupPoms=false '-DnewVersion=2024.1.0' 'org.codehaus.mojo:versions-maven-plugin:2.16.2:set'   -DprocessAllModules '-Dmaven.deploy.skip=true' -DskipITs '-Djacoco.skip=true'`

with maven 3.9.6 and jdk11, nothing is changed. The result looks like this:

```
[INFO] Searching for local aggregator root...
[INFO] Local aggregation root: D:\temp\maven-version\childproject\reactor
[INFO] Processing change of my.example.com.concrete:concrete-reactor:2024.1.0-SNAPSHOT -> 2024.1.0
[INFO] Processing my.example.com.concrete:concrete-reactor
[INFO]     Updating project my.example.com.concrete:concrete-reactor
[INFO]         from version 2024.1.0-SNAPSHOT to 2024.1.0
[INFO]     Updating project my.example.com.concrete:concrete-reactor
[INFO]         from version 2024.1.0 to 2024.1.0-SNAPSHOT
[INFO]
[INFO] Processing my.example.com.concrete:concrete-webapp
[INFO]     Updating project my.example.com.concrete:concrete-webapp
[INFO]         from version 2024.1.0-SNAPSHOT to 2024.1.0
[INFO]     Updating project my.example.com.concrete:concrete-webapp
[INFO]         from version 2024.1.0 to 2024.1.0-SNAPSHOT
```

When I use a different version like this (use version 2024.1.1 instead of 2024.1.0)

`mvn -DgenerateBackupPoms=false '-DnewVersion=2024.1.1' 'org.codehaus.mojo:versions-maven-plugin:2.16.2:set'   -DprocessAllModules '-Dmaven.deploy.skip=true' -DskipITs '-Djacoco.skip=true'`

the output looks like this and it works as expected:

```
[INFO] --- versions:2.16.2:set (default-cli) @ concrete-reactor ---
[INFO] Searching for local aggregator root...
[INFO] Local aggregation root: D:\temp\maven-version\childproject\reactor
[INFO] Processing change of my.example.com.concrete:concrete-reactor:2024.1.0-SNAPSHOT -> 2024.1.1
[INFO] Processing my.example.com.concrete:concrete-reactor
[INFO]     Updating project my.example.com.concrete:concrete-reactor
[INFO]         from version 2024.1.0-SNAPSHOT to 2024.1.1
[INFO]
[INFO] Processing my.example.com.concrete:concrete-webapp
[INFO]     Updating project my.example.com.concrete:concrete-webapp
[INFO]         from version 2024.1.0-SNAPSHOT to 2024.1.1
```

Project looks like this:

```
mainreactor
  |
  |   pom.xml (version 2024.1.0, no parent)
  |
  |---- pom-parent
  |         |
  |         |   pom.xml (version 2024.1.0 no parent)
  |
  |---- package-parent
  |         |
  |         |   pom.xml (version 2024.1.0, pom-parent as parent)


childreactor
  |
  |   pom.xml (version 2024.1.0-SNAPSHOT, parent mainreactor:pom-parent:2024.1.0)
  |
  |---- child-webapp
  |          |
  |          |   pom.xml (version 2024.1.0-SNAPSHOT, parent mainreactor:package-parent:2024.1.0)

```

I expect when setting the version via `versions:set` to 2024.1.0 the versions in the pom's from childproject are set to 2024.1.0 but they where "reset" to 2024.1.0-SNAPSHOT.

Main background: We using gitflow plugin to create releases and hotfixes and the gitflow plugin itself uses the versions plugin to update the versions to release and snapshot back. Because the versions plugin does not update the pom.xml the gitflow plugin fails because no changes where made.

See minimal example project which shows the behaviour. Please first run mvn install in mainproject/reactor and then go to childproject/reactor and try something like this:

`mvn -DgenerateBackupPoms=false '-DnewVersion=2024.1.0' 'org.codehaus.mojo:versions-maven-plugin:2.16.2:set'   -DprocessAllModules '-Dmaven.deploy.skip=true' -DskipITs '-Djacoco.skip=true'`

[maven-version.zip](https://github.com/mojohaus/versions/files/14095305/maven-version.zip)

### Additional contract requirements

- Add a static method `computeChildren(Map<File, Model> reactor)` in class `org.codehaus.mojo.versions.SetMojo`, accessible from the `org.codehaus.mojo.versions` package, returning `Map<org.apache.commons.lang3.tuple.Pair<String, String>, Set<Model>>`. Each key is a pair of the declared parent's groupId and artifactId, and each value is the set of models that declare that parent. Models without a parent must be omitted from the map.
