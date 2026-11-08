Boards/bots not in sync after update to v0.38.0
The following (using react client TicTacToe example with multilplayer local bots) shows two boards syncing every turn from player + bot in v0.37.2. Perfect!

```
...
const GameBoardClient = Client({
  game: TicTacToe,
  multiplayer: Local(
    { bots: { "1" : RandomBot } }
  ),
  board: Board,
});
...
```

```
...
<GameBoardClient playerID="0" matchID="match1" />
<GameBoardClient playerID="1" matchID="match1" />
...
```


Starting with v0.38.0 this is completely broken. Turns not synced to the other board + bot does not to change currentPlayer so that gameplay is broken. Ive seen other issues related to changing currentPlayer manually because this does not work by default - but it worked using v0.37.2. I tested multiple versions up to 40.0 the issue is definitely between v0.37.2...v0.38.0.

Additionally: The bot worked with only one board in v0.37.2 also because it changes the current player automatically like a bot should...

The issue must be here:
https://github.com/boardgameio/boardgame.io/compare/v0.37.2...v0.38.0
