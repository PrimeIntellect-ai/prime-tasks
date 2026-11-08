graphcache: 2.3.4: Invalid resolver data but no cache resolvers used
Upgrading from `@urql/exchange-graphcache: 2.3.3` to `2.3.4` I have a new warning in console:

```error
Invalid resolver data: The resolver at `Query.players({"input":{"first":20}})` returned an invalid typename that could not be reconciled with the cache.
(Caused At: Unnamed query)
https://bit.ly/38yWDau#8
```

which I can't reproduce [on Codesandbox](https://codesandbox.io/s/urql-svelte-graphcache-234-invalid-resolver-data-1c5ct) because of https://github.com/FormidableLabs/urql/issues/723.

I'm not using cache resolvers. I changed nothing in my code.

What changed is my cache in localStorage.

Below what I think is the problem:

With **2.3.3**

```json
{"Query\tplayers({\"input\":{\"first\":20}})":":\"Query.players({\\\"input\\\":{\\\"first\\\":20}})\"",
"Query.players({\"input\":{\"first\":20}})\tnodes":":[\"Player:2385\"]",
"Player:2385\tscore":"739404",
"Player:2385\tcreatedAt":"\"2020-04-20T21:16:29Z\"",
"Player:2385\tid":"\"2385\"",
"Player:2385\t__typename":"\"Player\"",
"Query.players({\"input\":{\"first\":20}})\t__typename":"\"PlayersConnection\""}
```

With **2.3.4**

```json
{"Query.players({\"input\":{\"first\":20}})":":\"Query.players({\\\"input\\\":{\\\"first\\\":20}})\"",
"Player:2385.score":"739404",
"Player:2385.createdAt":"\"2020-04-20T21:16:29Z\"",
"Player:2385.id":"\"2385\"",
"Player:2385.__typename":"\"Player\""}
```

As you can see with `2.3.4` there are no more:

1. `"Query.players({\"input\":{\"first\":20}})\tnodes":":[\"Player:2385\"]",` (maybe useless, maybe) and

1. `"Query.players({\"input\":{\"first\":20}})\t__typename":"\"PlayersConnection\""` which I think is what it complains about

### Additional contract requirements

- Embedded data written to persistent storage must remain available after the store is rehydrated, so a subsequent query returns the same embedded data.
