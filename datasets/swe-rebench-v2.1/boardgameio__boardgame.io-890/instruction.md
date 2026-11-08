No validation for games created on demand (by master.onSync)
If the socket client (re)connects to a game that has not yet been created, `onSync` attempts to create a game on the fly (see https://github.com/boardgameio/boardgame.io/blob/6c4e94fa7369c41098ccf6747689e091d818cbbe/src/master/master.ts#L392), [HIDDEN]

This is a completely different code path than the game creation via the REST API (https://github.com/boardgameio/boardgame.io/blob/d071e98c0868ea687d85168649e5d6302fb15229/src/server/api.ts#L128). [HIDDEN]

This results in `onSync` trying to create games with invalid values, rendering the validation useless.

In my case, this results in an error being thrown which in turn causes the entire server to die.

### Additional contract requirements

When `onSync` creates a match that does not yet exist, setup-data validation must reject invalid or missing setup data before that data is used to initialize the game. If validation rejects the data, the sync request must be handled without persisting an initialized invalid match.
