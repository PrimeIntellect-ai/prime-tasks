Using dashes in @Named results in "not a statement" compiler error
Example:
```java
@Factory
public class UserMaker {
    @Bean @Named("User-Id")
    String userId() {
        return "bla bla";
    }
}
```

```java
@DependencyMeta(type="java.lang.String", name="user-id", method="com...UserMaker$DI.build_userId", provides={"java.io.Serializable","java.lang.Comparable<java.lang.String>","java.lang.CharSequence","java.lang.constant.Constable","java.lang.constant.ConstantDesc"}, dependsOn={"com...UserMaker"}, autoProvides="java.io.Serializable")
  private void build_lang_String_user-id() {
    UserMaker$DI.build_userId(builder);
  }
```

Should avaje maybe normalize invalid characters into underscores?

Regards
