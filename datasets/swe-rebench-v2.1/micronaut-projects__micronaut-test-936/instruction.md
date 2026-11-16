JUnit Engine should be managed
### Feature description

There's an inconsistency in how we handle the test frameworks. With kotest, we can use:

```kotlin
    testImplementation(mnTest.micronaut.test.kotest5)
    testRuntimeOnly(mnTest.kotest.runner.junit5.jvm)
```

To get the JUnit5 runtime dependency. But we have no such thing for JUnit, which forces to declare a dependency:

```kotlin
    testImplementation(mnTest.micronaut.test.junit5)
    testImplementation("org.junit.jupiter:junit-jupiter-engine:5.9.2")
```

Note that this is in a `test-suite` project, not a user project which would apply the Micronaut Gradle plugin, but still, for consistency and users wanting to avoid our plugins, there should be a managed version of JUnit.

### Additional contract requirements

The build must expose managed JUnit Jupiter dependencies through the version catalog accessors `libs.managed.junit.jupiter.api`, `libs.managed.junit.jupiter.engine`, and `libs.managed.junit.jupiter.params`, resolving respectively to the `org.junit.jupiter:junit-jupiter-api`, `org.junit.jupiter:junit-jupiter-engine`, and `org.junit.jupiter:junit-jupiter-params` modules at the managed JUnit version.
