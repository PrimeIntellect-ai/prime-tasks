K8SSAND-1853 ⁃ Support additional jvm options for the various option files
Cassandra uses multiple jvm options files (`jvm.options`, `jvm-server.options`, `jvm8-server.options`, `jvm11-server.options`, `cassandra-env.sh`), and we're currently allowing to pass unstructured options to `cassandra-env.sh` only.

We'd need to have new `[]string` additional jvm options fields for each file in the `CassandraConfig.JvmOptions` struct:

```
config:
  jvmOptions:
      additionalJvmServerOptions:
        - '-XX:+UseConcMarkSweepGC'
        - '-XX:+UseCMSInitiatingOccupancyOnly'
        - '-XX:+CMSParallelInitialMarkEnabled'
      additionalJvm8ServerOptions:
        - '-XX:ThreadPriorityPolicy=42'
      additionalJvm11ServerOptions:
        - '-Djdk.attach.allowAttachSelf=true'
```

would map in the cassdc to:

```
  config:
    jvm-server-options:
      additional-jvm-opts:
        - '-XX:+UseConcMarkSweepGC'
        - '-XX:+UseCMSInitiatingOccupancyOnly'
        - '-XX:+CMSParallelInitialMarkEnabled'
    jvm11-server-options:
      additional-jvm-opts:
        - '-Djdk.attach.allowAttachSelf=true'
    jvm8-server-options:
      additional-jvm-opts:
        - '-XX:ThreadPriorityPolicy=42'
```

Additional options for the `cassandra-env.sh` would still be handled by the  `JvmOptions.AdditionalOptions` field as they currently are.


┆Issue is synchronized with this [Jira Task](https://k8ssandra.atlassian.net/browse/K8SSAND-1853) by [Unito](https://www.unito.io)
┆friendlyId: K8SSAND-1853
┆priority: Medium

### Additional contract requirements

The new fields are `AdditionalJvmServerOptions`, `AdditionalJvm8ServerOptions` and `AdditionalJvm11ServerOptions`, each a `[]string` on `CassandraConfig.JvmOptions` in package `apis/k8ssandra/v1alpha1`. `AdditionalJvmServerOptions` maps to the `additional-jvm-opts` entry of the `jvm-server-options` file, `AdditionalJvm8ServerOptions` maps to `jvm8-server-options`, and `AdditionalJvm11ServerOptions` maps to `jvm11-server-options`.
┆Issue is synchronized with this [Jira Task](https://k8ssandra.atlassian.net/browse/K8SSAND-1853) by [Unito](https://www.unito.io)
┆friendlyId: K8SSAND-1853
┆priority: Medium
