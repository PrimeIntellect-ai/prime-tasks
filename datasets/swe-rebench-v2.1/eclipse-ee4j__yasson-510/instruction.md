JsonbConfig fails to register serializer
**Describe the bug**
An issue with Yasson percolates to a bug in the Quarkus REST Client (escalated from https://github.com/quarkusio/quarkus/issues/15628):
When a serializer class doesn't explicitly implement `JsonbSerializer` but rather implicitly does so it will not be registered thus failing to serialize correctly.

**Expected behavior**
When a serializer is implicitly implementing `JsonbSerializer` it should be registered to correctly perform serialization.

**Actual behavior**
Serializer class that is explicitly implementing `JsonbSerializer` is not registered thus failing to serialize correctly.

**To Reproduce**

Clone the [example repo](https://github.com/sfrank-mc/rest-client-bug)

Steps to reproduce the behavior:
1. Have any echo server running at localhost:3000 (e.g. you can use [http-echo-server](https://www.npmjs.com/package/http-echo-server))
1. Enable [JsonConfig.java line 17](https://github.com/sfrank-mc/rest-client-bug/blob/main/app/src/main/java/rest/client/bug/JsonConfig.java#L17)
1. Disable [JsonConfig.java line 18](https://github.com/sfrank-mc/rest-client-bug/blob/main/app/src/main/java/rest/client/bug/JsonConfig.java#L18)
1. Run app (i.e. gradle run or any other way)
1. Notice the body is `[{"key":{"1111":"1","2222":"2"},"value":{"1111":"1","2222":"2"}}]`

1. Disable [JsonConfig.java line 17](https://github.com/sfrank-mc/rest-client-bug/blob/main/app/src/main/java/rest/client/bug/JsonConfig.java#L17)
1. Enable [JsonConfig.java line 18](https://github.com/sfrank-mc/rest-client-bug/blob/main/app/src/main/java/rest/client/bug/JsonConfig.java#L18)
1. Run app (i.e. gradle run or any other way)
1. Notice the body is `[{"key":{},"value":{}}]`

**Environment (please complete the following information):**
```
$ uname -a
Darwin mc-lon-mb15392 19.6.0 Darwin Kernel Version 19.6.0: Tue Jan 12 22:13:05 PST 2021; root:xnu-6153.141.16~1/RELEASE_X86_64 x86_64
$ java -version
openjdk version "11.0.7" 2020-04-14
OpenJDK Runtime Environment AdoptOpenJDK (build 11.0.7+10)
OpenJDK 64-Bit Server VM AdoptOpenJDK (build 11.0.7+10, mixed mode)
$ gradle --version
------------------------------------------------------------
Gradle 6.8.3
------------------------------------------------------------

Build time:   2021-02-22 16:13:28 UTC
Revision:     9e26b4a9ebb910eaa1b8da8ff8575e514bc61c78

Kotlin:       1.4.20
Groovy:       2.5.12
Ant:          Apache Ant(TM) version 1.10.9 compiled on September 27 2020
JVM:          11.0.7 (AdoptOpenJDK 11.0.7+10)
OS:           Mac OS X 10.15.7 x86_64
```
