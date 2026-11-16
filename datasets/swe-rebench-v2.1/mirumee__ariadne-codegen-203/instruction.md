GQL operation string is missing fragment used in a query
For the given GQL schema:
```graphql
type ItemA {
  valueA: String
}

type ItemB {
  valueB: String
}

union Item = ItemA | ItemB

type Container {
  name: String
  items: [Item]
}

type Query {
  container(id: ID!): Container
}
```

and following query:
```graphql
fragment ItemAFragment on ItemA {
  valueA
}

fragment ItemBFragment on ItemB {
  valueB
}

fragment ItemFragment on Item {
  ... on ItemA {
    ...ItemAFragment
  }
  ... on ItemB {
    ...ItemBFragment
  }
}

fragment ContainerFragment on Container {
  name
  items {
    ...ItemFragment
  }
}

query getContainer($id: ID!) {
  container(id: $id) {
    ...ContainerFragment
  }
}
```

the generated client contains the following `get_container` method:
```python
...
    async def get_container(self, id: str) -> GetContainer:
        query = gql(
            """
            query getContainer($id: ID!) {
              container(id: $id) {
                ...ContainerFragment
              }
            }

            fragment ContainerFragment on Container {
              name
              items {
                ...ItemFragment
              }
            }

            fragment ItemFragment on Item {
              ... on ItemA {
                ...ItemAFragment
              }
              ... on ItemB {
                ...ItemBFragment
              }
            }
            """
        )
...
```

Operation string is missing `ItemAFragment` and `ItemBFragment` definitions, even though they are used in `ItemFragment`.
