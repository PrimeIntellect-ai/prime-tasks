Feature Request - Allow to specify next phase using a function
**Problem:** Currently the `next` field in the phase configuration only accepts a string.

 I'm trying to write a phase using the `TurnOrder.ONCE` turn order, however the next phase needs to be determined dynamically. The only way to do this as far as I know is to specify an `endIf` function, but this clashes with automatic phase-ending `TurnOrder.ONCE`. I could write such a function, but especially since `endIf` is called before the phase is even begun, in my case the logic to accomplish this gets unnecesarily convoluted. It would be convenient if the `next` field accepted a function to allow to determine the next phase dynamically, without interfering with phase-ending logic.

### Additional contract requirements

- The `next` field of a phase configuration accepts either a phase name (a string) or a function `(G, ctx) => string | void`.
- When `next` is a function, it is invoked with the current game state `G` and the current context `ctx`, and the phase name it returns becomes the next phase.
- A `next` function that returns no phase name (`undefined`/`void`) results in no active phase.
