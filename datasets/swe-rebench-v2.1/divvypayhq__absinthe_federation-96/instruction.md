[federation] support new `@interfaceObject` directive
Apollo Federation v2.3 introduced new `@interfaceObject` directive that allows users to extend entity functionality through inheritance, i.e. given subgraph A

```graphql
interface Product {
 id: ID!
 title: String
}

# Book entity with key
type Book implements Product @key(fields: "id") {
 id: ID!
 title: String
 pages: Int
}

# Movie entity with key
type Movie implements Product @key(fields: "id") {
 id: ID!
 title: String
 duration: Int
}
```

We can generically extend the Product interface in other subgraphs by treating it as local object type with `@interfaceObject` directive. This new directive informs composition logic that it is actually an entity interface. This allows us to add new functionality in subgraph B without knowing any existing implementation details (i.e. without knowing anything about Book and Movie types).

```graphql
type Product @key(fields: "id") @interfaceObject {
 id: ID!
 reviews: [Review!]!
}

type Review {
 author: String
 text: String
 rating: Int
}
```

Additional resources:
* [@interfaceObject directive definition](https://www.apollographql.com/docs/federation/federated-types/federated-directives#interfaceobject)
* [Entity Interface documentation](https://www.apollographql.com/docs/federation/federated-types/interfaces)
* [Announcement blog post](https://www.apollographql.com/blog/announcement/platform/apollo-federation-and-graphos-add-support-for-entity-interfaces-to-streamline-collaboration/)

---
New directive functionality can be tested using [Apollo Federation Subgraph Compatibility](https://www.npmjs.com/package/@apollo/federation-subgraph-compatibility) NPX script (and [Github Action](https://github.com/marketplace/actions/apollo-federation-subgraph-compatibility)). Example integration project is already provided in the [subgraph compatibility testing repository](https://github.com/apollographql/apollo-federation-subgraph-compatibility/tree/main/implementations/absinthe-federation).
