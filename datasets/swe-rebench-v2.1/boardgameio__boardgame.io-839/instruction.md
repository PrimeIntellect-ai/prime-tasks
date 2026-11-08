Keep track of players' connection status
It would be useful to keep track of all players' connections status and broadcast that info to other players. This would allow displaying connection status next to player info and let other players know that they are currently unavailable due to e.g. network issues.

I think the best place to store that info is `matchData`
```
[
  { id: 0, name: 'Alice', isConnected: true },
  { id: 1, name: 'Bob', isConnected: false }
]
```

It could use server-side SocketIO connect/disconnect events to modify `matchData` and broadcast that info independently of game state.

If you think it's a nice-to-have feature in the framework I'd be happy to work on it and prepare a PR.

### Additional contract requirements

- Add a public method `onConnectionChange(matchID: string, playerID: string, connected: boolean)` on `Master` in `src/master/master.ts`. It returns a Promise.
- The method records the player's connection status in the match metadata under `isConnected`, persists the updated metadata, and broadcasts the updated player metadata to all connected clients as a message of type `'matchData'` whose arguments are the matchID and the updated player metadata.
- When the match metadata cannot be found, the method resolves to `{ error: 'metadata not found' }` and logs exactly `metadata not found for matchID=[${matchID}]`.
- When the player does not belong to the match, the method resolves to `{ error: 'player not in the match' }` and logs exactly `Player not in the match, matchID=[${matchID}] playerID=[${playerID}]`.
- The server calls `onConnectionChange` with `connected` set to `true` when a Socket.IO client connects and `false` when it disconnects.
