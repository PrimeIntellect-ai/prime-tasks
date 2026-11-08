Variable validation for list variables is too strict
The following operation does not validate but should:
```
# Operation
query myQuery($arg: [String!]) {
    someQuery(arg: $arg)
}

# Schema
type Query {
    someQuery(arg: [String]): String
}
```
In this example, `[String!]` is more strict than `[String]` and is compatible per the GraphQL spec: https://spec.graphql.org/June2018/#AreTypesCompatible().

Validation returns the error:
```
value: $arg doesn't satisfy inputType: [String]
```

### Additional contract requirements

Variable-to-argument compatibility must be checked recursively through list and non-null wrappers. A non-null variable type may be used where the argument type is nullable, while a nullable variable type is not compatible with a non-null argument type unless the applicable GraphQL default-value exception permits it. After wrapper compatibility is accounted for, the named input types must agree; matching wrapper shapes do not make different named types compatible.
