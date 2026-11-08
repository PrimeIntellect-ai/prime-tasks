Why use a `BiFunction` when the desired interface was a `BiPredicate`?
### Describe the feature request

In the `Unleash` interface, there are some methods with a `BiFunction<String, UnleashContext, Boolean>` argument. But the availables implementations for `Unleash` (`DefaultUnleash`, `FakeUnleash`) both have no safe measures against this function returning a `null`. Bot will yield a `NullPointerException`:

[`DefaultUnleash.java#L123-L127`](https://github.com/Unleash/unleash-client-java/blob/8525a8f56e2198bebcd893e169ae92b556cc8b07/src/main/java/io/getunleash/DefaultUnleash.java#L123-L127)

```java
        boolean enabled;
        UnleashContext enhancedContext = context.applyStaticFields(config);

        if (featureToggle == null) {
            enabled = fallbackAction.apply(toggleName, enhancedContext);
```

[`FakeUnleash.java#L43-L46`](https://github.com/Unleash/unleash-client-java/blob/8525a8f56e2198bebcd893e169ae92b556cc8b07/src/main/java/io/getunleash/FakeUnleash.java#L43-L46):

```java
    public boolean isEnabled(
            String toggleName, BiFunction<String, UnleashContext, Boolean> fallbackAction) {
        if (!features.containsKey(toggleName)) {
            return fallbackAction.apply(toggleName, UnleashContext.builder().build());
```

Also, it is more semantic to use `Predicate<T>` or similar instead of `Function<T, Boolean>` or similar.

### Background

Using `Predicate<T>` instead of `Function<T, Boolean>` is a lot more semantic, and also avoids (some) random null pointer exceptions that the java type system allows.

If the null pointer exception happens for some reason, it will be a violation of contract of the API consumer, not of the API provider, as it is now.

### Solution suggestions

[HIDDEN]

It is wildly expected that it shall be ok with the use of lambdas. It will break compatibility if someone passes directly an instance of `BiFunction<String, UnleashContext, Boolean>`, as the tests within here have broken.

Trying to accept both `BiPredicate<String, UnleashContext>` and `BiFunction<String, UnleashContext, Boolean>` will cause the compiler to get confused, as both will satisfy the lambda signature. For example, in `DefaultUnleash` will yield a compiler error:

```java
    @Override
    public boolean isEnabled(
            final String toggleName, final UnleashContext context, final boolean defaultSetting) {
        return isEnabled(
                toggleName,
                context,
                (n, c) -> defaultSetting);
    }
```

![ambiguous method call, both functional interfaces match](https://user-images.githubusercontent.com/6178379/196252564-4c1261f9-a6b7-4961-9b6f-9524b3953442.png)

[HIDDEN]

### Additional contract requirements

- Fallback callbacks for the affected `Unleash.isEnabled` overloads must produce a non-null boolean decision. If a toggle is missing, its fallback decision determines the result; a null callback result must not cause an unboxing `NullPointerException`.
