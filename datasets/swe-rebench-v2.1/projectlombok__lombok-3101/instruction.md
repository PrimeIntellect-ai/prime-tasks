[BUG] @UtilityClass fails to make inner class static in Java 9+
**Describe the bug**

When a class is annotated with `@UtilityClass`, and this class has an inner class, the inner class is also treated as `static` in Java 1.8, but is not treated as `static` in Java 9 and later. This causes compilation failure under Java 9+ for code that compiled correctly in Java 1.8.

**To Reproduce**

Save the following as `Outer.java`:

```java
import lombok.experimental.UtilityClass;

@UtilityClass
class Outer {

  Object buildInner() {
    return new Inner();
  }

  class Inner {}
}
```

Compile this file using `javac` from Java 1.8, and observe that compilation succeeds with no diagnostic output:

```text
% /path/to/java-1.8/bin/javac -cp lombok.jar Outer.java
```

Now compile this file using `javac` from Java 9 or later, and observe that compilation fails:

```text
% /path/to/java-9/bin/javac -cp lombok.jar Outer.java
Outer.java:7: error: non-static variable this cannot be referenced from a static context
    return new Inner();
           ^
1 error
```

**Expected behavior**

Java 9 and later compilers should have compiled this source file, producing no diagnostic output.

**Version info (please complete the following information):**
 - Lombok version: 1.18.22
 - Platform: `javac` 9

**Additional context**

The problem first arises with Java 9, but also occurs in Java 11, 14, and 17. (I haven't tested Java 10, 12, 13, 15, or 16.)

#2519 seems closely related, but was closed because it could not be reproduced. However, that earlier report mentioned nothing about different Java versions. In this new report, I find that the Java compiler version is critical: the problem only arises in Java 9 and later, not in Java 1.8.
