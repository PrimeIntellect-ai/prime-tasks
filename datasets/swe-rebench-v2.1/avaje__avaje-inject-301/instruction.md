Map Beans not detected
suppose I have a factory that provides

```java
  @Bean
  Map<String, Model> map() {

    return Map.of("hi",  new Model, ....);
  }
```

When I rely on this bean somewhere else.

```java
  @Bean
  SomeOtherBean otherBean( Map<String, Model> s) {
....
  }
```
I get this exception.


[ERROR] Dependencies [Model] are not provided - missing @Singleton, @Component, @Factory/@Bean or specify external dependency via @InjectModule requires attribute

One would expect that the map from the factory would be detected.

### Additional contract requirements

A map returned by a factory is injectable as the declared `Map` bean type, including when its value type is not independently registered as a bean. The existing map-of-beans keyed by qualifier name remains available through an explicitly marked injection point; in this repository, `@QualifiedMap` is the marker for that behavior. Unmarked map injection uses the factory-provided map bean.
