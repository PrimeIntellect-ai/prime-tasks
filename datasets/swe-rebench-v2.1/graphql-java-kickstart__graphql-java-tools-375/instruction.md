Remove Guava dependency
Guava is a big library (2.7 MB), and the dependency of graphql-java-tools on Guava is quite loose, as pointed out already in #283.

There are only 2 functionalities used from Guava:
- Primitives::wrap - wraps a primitive (like int.class) to the corresponding class (e.g. Integer.class). This can be trivially replaced.
- BiMap - used to back the type dictionary. It can also be easily replaced.

Removing Guava is desirable for projects that use graphql-java-tools because:
- they may not need Guava at all, since they rely on other open source libraries with similar features (e.g. appache-commons-*)
- they may not want the headache of managing different versions of the Guava library. For example, graphql-java-tools uses v26.0, graphql-java-servlet uses 24.1.1 and the latest version is 28.2

I'll provide a pull request that removes the Guava dependency.

### Additional contract requirements

Add the following public API in the package `graphql.kickstart.tools.util`:

- A public class `BiMap<K, V>` that implements `java.util.Map<K, V>` and keeps a one-to-one association between keys and values.
  - `public static <K, V> BiMap<K, V> create()` returns a new, empty, mutable `BiMap`.
  - `public V put(K key, V value)` associates `value` with `key` and returns the value previously associated with `key`, or `null` if `key` had no mapping. It throws `IllegalArgumentException` if `value` is already associated with a different key.
  - `public BiMap<V, K> inverse()` returns a `BiMap` whose keys are the original values and whose values are the original keys.
  - `public Set<V> values()` returns the set of values currently present.
  - `public V get(Object key)` returns the value associated with `key`, or `null` if there is no mapping.
- A public class `Primitives` with `public static <T> Class<T> wrap(Class<T> type)` that returns the wrapper class for a primitive class (`boolean` to `Boolean`, `byte` to `Byte`, `char` to `Character`, `double` to `Double`, `float` to `Float`, `int` to `Integer`, `long` to `Long`, `short` to `Short`, `void` to `Void`), returns `type` unchanged when it is not a primitive, and returns `null` when `type` is `null`.
