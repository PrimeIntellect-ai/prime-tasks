Add playerView option to plugin API
Currently games can define a `playerView` to exclude secret state from the `G` that is returned to clients.

As mentioned in #668, plugins should also be able to hide secret state on the client, for example using a `playerView` option:

```js
const plugin = {
  playerView: ({ G, ctx, game, data, playerID }) => data without secrets,
}
```

We would then have to call the plugins’ `playerView` for each update sent to clients.
