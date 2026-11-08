Updating logging functions for spying after framework is loaded
Tangentially related to #592, I propose we update how we call the logging methods `console.error` and `console.log` so they can be properly spied upon during tests after the framework has loaded.

For context i'm using Angular CLI to generate an app. I then pull in boardgame.io and start writing tests. Angular CLI is using Typescript  4.1.2 and jasmine 3.6.0. When writing a test it looks something like this:

```
import { Client } from 'boardgame.io/client';
...


describe('MyGame', () => {
  beforeEach(() => {
    spyOn(console, 'error');
    game = Client({ game: MyGame });
    ...
  });

  it('should not do a thing', () => {
    game.moves.someMove();
    expect(console.error).toHaveBeenCalledWith('ERROR:', `disallowed move: someMove`);
  });
});
```

At the moment the expectation will fail because the boardgame code is being loaded before the spy can be created. Per #592 there is no other good way to determine if an invalid move has been made (without in depth state checking) so spying on the error logs is the only other approach. Although I suspect spying on the logs can provide other test benefits besides just invalid move testing. Since the boardgame code is binding directly to the `console.error` function reference there is no way to spy on it after the fact.

IF spying on logging functions after the codebase has been loaded is a valid use-case then I can think of two possible approaches:
1. Allowing the client to provide both a log and error function which defaults to `console.XYZ` method, respectively.
[HIDDEN]

### Additional contract requirements

- When boardgame.io logs a message, it must use the current `console.log` function at the time of the logging call, so a spy installed after the framework is loaded can observe the call.
- When boardgame.io reports an error, it must use the current `console.error` function at the time of the logging call, so a spy installed after the framework is loaded can observe the call.
