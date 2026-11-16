Is it not possible to query __typename field
We could not query `__typename` field in case it is not specified in schema for each type
query:
```graphql
query getApi($id: String!) {
  api(id: $id) {
      __typename
    ... on Api {
      __typename
      id
      name
    }

    ... on RequestResult {
      __typename
      status
      message
    }
  }
}

```

graphql server returns an error:
```
[Jan 21 17:29:58] ERROR executionHandler.Handle error=external: field: __typename not defined on type: Query, locations: [], path: [query]
[Jan 21 17:30:12] ERROR executionHandler.Handle error=external: field: __typename not defined on type: Api, locations: [], path: [query,api]
[Jan 21 17:30:18] ERROR executionHandler.Handle error=external: field: __typename not defined on type: ApiResult, locations: [], path: [query,api]
```
