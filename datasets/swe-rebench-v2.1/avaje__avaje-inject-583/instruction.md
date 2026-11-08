Named Map beans not working for versions > 9.10
Hello there,

while bumping dependencies (from 9.10-javax to 9.12-javax) my DI setup stopped working. I reproduced the issue in a minimal example:
```java
@Factory
public class ConfigFactory {
    @Bean
    @Named("map1")
    Map<String, Long> map1() {
        return Map.of();
    }

    @Bean
    @Named("map2")
    Map<String, String> map2(Map<String, Long> map1) {
        return Map.of();
    }
}
```
Any advice?

Thanks!

PS: Actually I just realized that dependencies injected via method arguments are not matched by name but by type - is there any way to match them by name? Something like Spring's `@Qualifier`.

### Additional contract requirements

Factory-produced beans with different generic map types must remain independently retrievable by their full generic types. When a factory method accepts a `Map<String, Long>`, that parameter must resolve to the `Map<String, Long>` bean, not a bean whose map has a different value type.
