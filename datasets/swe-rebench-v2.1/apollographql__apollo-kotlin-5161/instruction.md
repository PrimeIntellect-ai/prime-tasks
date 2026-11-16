Increase the maximum JSON nesting level, or make it customisable
### Use case

I am querying a page of nested comments from a certain API, and getting an exception: `JsonDataException - Nesting too deep at [data, Page, threadComments, 0, childComments, 0, childComments, 0, childComments, 0, childComments, 0 ...`. Looking at past issues (#3308), I can see that the limited used to be 32 and was increased to 256. And the JSON response I am getting indeed has very deep nesting, however, it is a valid response and I want it to be parsed


### Describe the solution you'd like

I propose to either increase the nesting level limit further, or to make it possible to customize/change the limit (eg in the `ApolloClient.Builder`) so that it can be increased in cases like mine

### Additional contract requirements

- `com.apollographql.apollo3.api.json.MapJsonReader` is a public `JsonReader` that can be constructed from a root `Map<String, Any?>`.
- `com.apollographql.apollo3.api.json.jsonReader` is a public extension function on `okio.BufferedSource` that returns a `JsonReader`.
- `com.apollographql.apollo3.api.json.readAny` is a public extension function on `JsonReader` that consumes the whole document and returns its value as Kotlin types (`Map`, `List`, `String`, `Number`, `Boolean`, or `null`).
- A JSON document nested at least 1025 levels deep must be readable through these entry points without a "Nesting too deep" error.
