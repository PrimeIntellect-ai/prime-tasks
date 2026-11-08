Always call `loadPersistedQuery` if `queryId` was provided
Hey.

`graphql-php` conveniently provides means of implementing persisted queries - namely, it parses `queryId` from the request. The usual strategy is called Apollo automatic persisted queries - find the query in cache, return if found, cache if not found. This is implemented by all major GraphQL libraries: Apollo Server, Hot Chocolate, ExpediaGroup/graphQL.

The process is described in detail here: https://www.apollographql.com/docs/apollo-server/performance/apq/

This would have worked in `graphql-php` too, but there's a small stopper which prevents us from doing so: https://github.com/webonyx/graphql-php/blob/master/src/Server/Helper.php#L258. If `queryId` and `query` are both provided (as is the case when a query by ID wasn't initially found), then persisted query loader isn't executed, meaning there's no way to actually save the query into cache.

This can be worked around in userland by overwriting `Helper::promiseToExecuteOperation`, but that isn't an elegant solution to what seems to be just a precaution of the past. [HIDDEN]

Would this kind of change be accepted? If so, I'll PR the change.

### Additional contract requirements

- When a request includes a `queryId`, use the persisted-query loader to resolve the operation even if the request also includes a `query`.
