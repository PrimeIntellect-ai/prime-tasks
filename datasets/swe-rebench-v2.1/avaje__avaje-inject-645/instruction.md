Dependency information for qualified beans does not include qualified name, resulting in incorrect circular dependency detection
Given the following code:
```java
// test/IncorrectCircularDependency.java
package test;

import io.avaje.inject.Bean;
import io.avaje.inject.Factory;
import jakarta.inject.Named;
import jakarta.inject.Singleton;

@Singleton
@Factory
public class IncorrectCircularDependency {
    @Bean
    @Named("parent") // for clarity, not necessary
    public String parent(@Named("child") String child) {
        throw new AssertionError("Method body unimportant");
    }

    @Bean
    @Named("child")
    public String child() {
        throw new AssertionError("Method body unimportant");
    }
}
```
```java
// test/Test.java
package test;

import jakarta.inject.Inject;
import jakarta.inject.Singleton;

@Singleton
public class Test {
    private final String parent;

    @Inject
    public Test(@Named("parent") String parent) {
        this.parent = parent;
    }

    public String getParent() {
        return parent;
    }
}
```

Despite the clearly non-circular dependency from `parent` to `child`, due to the dependency of `parent` incorrectly not using the `child` qualifier and depending on itself, avaje-inject spits out this error:
```
error: Circular dependencies detected with beans [java.lang.String:parent, test.Test]  To handle circular dependencies consider using field injection rather than constructor injection on one of the dependencies.
   See https://avaje.io/inject/#circular
error: Circular dependency - java.lang.String:parent dependsOn java.lang.String:parent for java.lang.String
error: Circular dependency - test.Test dependsOn java.lang.String:parent for java.lang.String
```

This should not be an error and should compile cleanly.
