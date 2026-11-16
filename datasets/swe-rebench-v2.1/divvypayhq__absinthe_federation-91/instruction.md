[federation] support new `@composeDirective`
Apollo Federation v2.1 introduced new `@composeDirective` directive that allows users to specify directives that should be preserved in the supergraph composition (by default composition strips out most directives from supergraph).

```graphql
extend schema
  @link(
    url: "https://specs.apollo.dev/federation/v2.3",
    import: ["@composeDirective", "@extends", "@external", "@key", "@inaccessible", "@interfaceObject", "@override", "@provides", "@requires", "@shareable", "@tag"]
  )
  @link(url: "https://myspecs.dev/myCustomDirective/v1.0", import: ["@custom"])
  @composeDirective(name: "@custom")

// will be present in the supergraph definition
directive @custom on OBJECT

type Product @custom @key(fields: "id")
  id: ID!
  // other fields omitted for clarity
}
```

Additional resources:
* [`@composeDirective` directive definition](https://www.apollographql.com/docs/federation/federated-types/federated-directives#composedirective)

---
New directive functionality can be tested using [Apollo Federation Subgraph Compatibility](https://www.npmjs.com/package/@apollo/federation-subgraph-compatibility) NPX script (and [Github Action](https://github.com/marketplace/actions/apollo-federation-subgraph-compatibility)). Example integration project is already provided in the [subgraph compatibility testing repository](https://github.com/apollographql/apollo-federation-subgraph-compatibility/tree/main/implementations/absinthe-federation).
