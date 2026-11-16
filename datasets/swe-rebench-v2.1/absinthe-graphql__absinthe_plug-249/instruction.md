upgrade from 1.5.3 to 1.5.4 breaks default pub sub option
The upgrade from 1.5.3 to 1.5.4 broke our application. We didn't set the `pubsub` option explicitly, but relied on the default `conn.private[:phoenix_endpoint]`. After the upgrade, this default apparently gets overwritten by the `update_config` function. We noticed because subscription triggers still worked when pushing mutations via a socket, but they didn't work anymore when sending a mutation via HTTP.

### Additional contract requirements

For HTTP GraphQL requests, when no pubsub override is configured, preserve the Phoenix endpoint's default pubsub alongside other request-level context values so subscription triggers continue to work for mutations sent over HTTP.
