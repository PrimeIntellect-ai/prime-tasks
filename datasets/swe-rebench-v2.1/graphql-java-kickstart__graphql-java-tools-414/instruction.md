Circular input property leads to stackoverflow
After updating graphql-java-tools to 6.1.0 i have encountered a stackoverflow exception on startup. I think that the problem was introduced in this commit: https://github.com/graphql-java-kickstart/graphql-java-tools/commit/10ee43f3e00f25194323a6ab7c1a9a4481726ca6 and happens because of the interaction between `determineInputType` and `createInputObject`.
Example schema:

```
input A {
    id: ID!
    b: B
}

input B {
   id: ID!
   a: A
}
```

According to the spec this should be allowed (https://github.com/graphql/graphql-spec/pull/445, https://github.com/graphql/graphql-spec/issues/189), which leads me to believe that this is a bug.
