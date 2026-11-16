Cannot read property 'prngstate' of undefined
After upgrading to [v0.42.0](https://github.com/boardgameio/boardgame.io/tree/v0.42.0) the `random.D6` function is returning the following error
```
:3000/static/js/0.chunk.js:45834 Uncaught TypeError: Cannot read property 'prngstate' of undefined
    at Random._random (:3000/static/js/0.chunk.js:18067)
    at :3000/static/js/0.chunk.js:18097
    at Array.map (<anonymous>)
    at Object.predefined.<computed> [as D6] (:3000/static/js/0.chunk.js:18097)
    at Dice.roll (:3000/static/js/main.chunk.js:17418)
    at attackDiceMatch (:3000/static/js/main.chunk.js:16633)
    at :3000/static/js/0.chunk.js:17921
    at e.i.produce (:3000/static/js/0.chunk.js:20002)
    at :3000/static/js/0.chunk.js:17920
    at Object.processMove (:3000/static/js/0.chunk.js:16614)
    at :3000/static/js/0.chunk.js:16817
    at dispatch (:3000/static/js/0.chunk.js:155791)
    at :3000/static/js/0.chunk.js:13689
    at :3000/static/js/0.chunk.js:13745
    at Object.dispatch (:3000/static/js/0.chunk.js:13759)
    at Object.dispatchers.<computed> [as attackDiceMatch] (:3000/static/js/0.chunk.js:13612)
    at attackerDiceRoll (:3000/static/js/main.chunk.js:9661)
    at HTMLUnknownElement.callCallback (:3000/static/js/0.chunk.js:45688)
    at Object.invokeGuardedCallbackDev (:3000/static/js/0.chunk.js:45737)
    at invokeGuardedCallback (:3000/static/js/0.chunk.js:45797)
    at invokeGuardedCallbackAndCatchFirstError (:3000/static/js/0.chunk.js:45812)
    at executeDispatch (:3000/static/js/0.chunk.js:50047)
    at processDispatchQueueItemsInOrder (:3000/static/js/0.chunk.js:50079)
    at processDispatchQueue (:3000/static/js/0.chunk.js:50092)
    at dispatchEventsForPlugins (:3000/static/js/0.chunk.js:50103)
    at :3000/static/js/0.chunk.js:50314
    at batchedEventUpdates$1 (:3000/static/js/0.chunk.js:63999)
    at batchedEventUpdates (:3000/static/js/0.chunk.js:45486)
    at dispatchEventForPluginEventSystem (:3000/static/js/0.chunk.js:50313)
    at attemptToDispatchEvent (:3000/static/js/0.chunk.js:47796)
    at dispatchEvent (:3000/static/js/0.chunk.js:47714)
    at unstable_runWithPriority (:3000/static/js/0.chunk.js:157401)
    at runWithPriority$1 (:3000/static/js/0.chunk.js:53094)
    at discreteUpdates$1 (:3000/static/js/0.chunk.js:64016)
    at discreteUpdates (:3000/static/js/0.chunk.js:45498)
    at dispatchDiscreteEvent (:3000/static/js/0.chunk.js:47680)
```

I'm calling the function within a class.
```ts
import { Ctx } from "boardgame.io";
import { GStatus } from "../types/game";

export class Dice {
  G: GStatus;
  ctx: Ctx;

  constructor(GameStatus: GStatus, context: Ctx) {
    this.G = GameStatus;
    this.ctx = context;
  }

  roll(numberOfDice: number) {
    return this.ctx!.random!.D6(numberOfDice).sort().reverse();
  }
}
```

Apparently, the unexpected behaviour is related to the changes in this PR: https://github.com/boardgameio/boardgame.io/pull/841
