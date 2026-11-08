Best practices for handling optional arguments?
We just updated graphql-java-tools from 5.4.1 and the biggest change is around nullable input fields (I think caused by https://github.com/graphql-java-kickstart/graphql-java-tools/pull/315).

Previously, we were defining our resolver methods with `Optional<>` arguments for those that are nullable in the schema, e.g. `first` in

```graphqls
customers(input: CustomerSearchInput!, first: Int): [Customer!]
```

... mapped to the following resolver method:

```java
public List<Customer> getCustomers(CustomerSearchInput input, Optional<Integer> first) { ... }
```

Previously, the `first` argument was `Optional.empty()` regardless of whether the client passed an explicit `first: null` or didn't pass the argument at all. However, now we are getting `null` when the client doesn't pass the argument, which requires us to handle both `null` and `Optional.empty` in all resolver methods with optional arguments.

Is there a way to opt-out of this new behavior? Or if not, a recommended way to unify handling of `null` and absence? e.g. in the object mapper configurer or something?

### Additional contract requirements

For a nullable GraphQL argument whose resolver parameter is `Optional<T>`, omitting the argument must be handled the same way as explicitly passing `null`: the resolver receives an empty Optional, not `null`.
