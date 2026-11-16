__typename not merged
When i start server with `go run example/starwars/server/server.go` and execute this query :
```
query TestMerge {
  hero {
    __typename
    name

    ... on Character {
      ...Droid
      name
      __typename
    }

  }
}

fragment Droid on Droid {
  name
  __typename
}
```

GraphiQL merge __typename field but the server response has multiple __typename.
Result with server response (browser network inspect) :
```
{"data":{"hero":{"__typename":"Droid","name":"R2-D2","__typename":"Droid","__typename":"Droid"}}}
```

Expected :
```
{"data":{"hero":{"name":"R2-D2","__typename":"Droid"}}}
```
With graphql-js __typename is merged.

link #365

### Additional contract requirements

- For this query, the serialized data object, excluding the outer `data` envelope, must be exactly `{"hero":{"__typename":"Droid","name":"R2-D2"}}`.
