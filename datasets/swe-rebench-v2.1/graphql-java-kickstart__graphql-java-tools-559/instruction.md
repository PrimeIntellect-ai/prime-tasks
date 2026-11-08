Expected object type [...] to exist for union
<!-- ⚠️ Please ensure you are reporting the bug in the correct repository! -->

## Description

Suppose we have a union U = Foo | Bar and GraphQL type Bar is mapped to the Java interface Bar. In this case the concrete value for type Bar must be a class that implements Bar, i.e.:
```java
public interface Bar { ... }
public class BarImpl implements Bar { ... }

// and then a resolver method somewhere (GraphQL signature is `fooOrBar: U!`):
public Object getFooOrBar() { return new BarImpl(...); }
```
The UnionTypeResolver supports this scenario due to [PR 140](https://github.com/graphql-java-kickstart/graphql-java-tools/pull/140), which looks at the direct interfaces of the value.

However, if the type hierarchy is a bit more complex it will fail. Suppose we have an additional intermediate interface:
```java
public interface Bar { ... }
public interface BarEntity { ... }
public class BarEntityImpl implements BarEntity { ... }

// and then a resolver method somewhere (GraphQL signature is `fooOrBar: U!`)
public Object getFooOrBar() { return new BarEntityImpl(...); }
```
In this case the resolver will fail to resolve the type, since GraphQL type Bar is mapped to interface Bar, and that's not a direct superinterface of BarEntityImpl.

### Expected behavior

I would expect class BarEntityImpl to succesfully resolve to GraphQL type Bar, since it implements (indirectly) interface Bar.

### Actual behavior

Resolving fails with error "Expected object type with name 'BarEntityImpl' to exist for union 'U', but it doesn't!".

### Steps to reproduce the bug

Pull request #559 reproduces this issue.
