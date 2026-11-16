SSR pages re-executing queries
Hi :wave:

I've been debugging an issue where SSR pages are re-executing queries on the client (some of the time).

I believe this is caused by `cacheExchange` mutating `operation.query` when it [calls `formatDocument(operation.query)`](https://github.com/FormidableLabs/urql/blob/e6e2fa9/packages/core/src/exchanges/cache.ts#L28).

There is a [comment](https://github.com/FormidableLabs/urql/blob/ec8c318/packages/core/src/utils/typenames.ts#L43) in `formatDocument()` which explains that mutating the `node` is ok because `visit()` clones the AST upwards. Although `visit()` does clone the AST upwards, it looks like mutating the `node` still mutates the original `operation.query` which is used when computing the query `__key`.

This issue only appears intermittently and likely with a specific version of node. I've managed to reproduce this issue locally using node `v10.20.1` and a production webpack build of our app. I have confirmed we see different `__key`'s for the same query on the client and server due to additional `__typename` entries on the server side only. [HIDDEN], which suggests mutating the node is the cause.

Looking at other active issues, https://github.com/FormidableLabs/urql/issues/874 may be related.

urql version & exchanges: `1.9.5` `cacheExchange`

Thanks :)

### Additional contract requirements

Formatting a query must leave the original `DocumentNode` unchanged. Formatting must also preserve the request key for that same query.
