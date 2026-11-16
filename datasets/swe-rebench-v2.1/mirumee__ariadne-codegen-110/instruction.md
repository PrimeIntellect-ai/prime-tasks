Handle query and mutation types names
Reported in #100
Given schema with query type with a different name than `Query` (the same for mutation type and name `Mutation`), eg.
```gql
schema {
    query: query_type
}

type query_type {
    test: String!
}
```
and operation
```gql
query Abc {
    test
}
```
`ariadne-codegen` doesn't generate client but raises exception instead, eg. `ariadne_codegen.exceptions.ParsingError: Field test not found in type Query.`
