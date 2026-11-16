make object variable arguments available to templating engine
Currently only ".arguments" and ".request.headers" are available to the templating engine. The current parent object during execution should also be available to the templating engine. That is, in order to fetch related object it's necessary to access fields from the parent object. E.g. you fetch all friends who contain an "ID". This id should be available to the templating engine to form requests to retrieve all friends pets.

Possible syntax:

```graphql
type JSONPlaceholderPost {
    userId: Int!
    id: Int!
    title: String!
    body: String!
    comments: [JSONPlaceholderComment]
    @HttpJsonDataSource(
        host: "jsonplaceholder.typicode.com"
        url: "/comments?postId={{ .object.id }}"
    )
    @mapping(mode: NONE)
}
```
