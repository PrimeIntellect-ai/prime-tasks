Use storage.createGame for implicit match creation
Currently if the game master receives a sync event for a non-existent `matchID` it initialises that match implicitly:

https://github.com/boardgameio/boardgame.io/blob/9a2a6098da9b651a823c7a4f20956ffb6afe89e5/src/master/master.ts#L380-L395

This code persists the game state using the storage layer’s `setState` method. This can create inconsistencies, because the match’s initial state isn’t stored and any other game creation logic a storage layer might implement won’t be triggered. The storage layer’s `createGame` should be used here instead.

This might not always produce errors, but I ran into it [in the Firestore connector today](https://github.com/delucis/bgio-firebase/issues/5#issuecomment-638962576), because I was initialising the log document as an empty array in `createGame` and then appending to it subsequently. Matches created implicitly then caused errors, because we were trying to append to the uninitialized log.

### Additional contract requirements

- When a sync request is received for a match that does not exist, the match is created through the storage layer's match-creation method (`createMatch`) rather than by persisting only the current state, so that both the match's initial state and its match metadata are stored.
- `Master.onSync(matchID: string, playerID: string, numPlayers?: number)` accepts an omitted `numPlayers` and defaults it to 2 for a newly created match.
- Add a public function `createMetadata({ game, numPlayers, setupData?, unlisted? })` in module `src/server/util` that returns a fully-formed `Server.MatchData` object containing the game name, one player slot per player, creation and update timestamps, and the optional setup data.
