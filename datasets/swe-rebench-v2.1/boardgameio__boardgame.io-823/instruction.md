Undo / redo validity condition seems wrong in the presence of stages
Currently it says:

https://github.com/boardgameio/boardgame.io/blob/60b32e5d786446914106743f569539269cc1b577/src/master/master.ts#L242-L253

But `activePlayers` can be non-null and there is only one valid player. For example:

```
activePlayers: {0: "selectColor"}
```

It seems to me that undo should be allowed in this case.
