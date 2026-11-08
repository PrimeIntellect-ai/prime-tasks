Browser API: logEvent.messages cuts off first/main message
Thank you for building this universal solution. Very nice.

However I'm running into an issue when logging in a browser. The goal is to use the `send` method to post the message to a backend service.

Here is my code:

```js
const logger = require('pino')({
  browser: {
    asObject: true,
    transmit: {
      level: 'warn',
      send(level, logEvent) {
        console.log('the event', level, logEvent.messages);
      }
    }
  }
});

logger.info('hello world');
logger.warn('look out world');
logger.error('goodbye world', 'something else');
```

...and the pino logger output when run both client and server-side (ignoring `pid`/`hostname`/`v`):

```bash
{"level":30,"time":1547591483164,"msg":"hello world"}
{"level":40,"time":1547591483164,"msg":"look out world"}
{"level":50,"time":1547591483164,"msg":"goodbye world something else"}
```
Great!

Also, the `send` function is correctly only running for `warn` and `error` (given the minimum level in the `transmit` configuration). However, the `send` method is not holding the right messages. Here is the `console.log` output:

```
the event warn []
the event error ["something else"]
```

This gives me the idea that the first argument passed into `logger.[verb]()` is ignored. However, the [documentation](https://getpino.io/#/docs/browser?id=transmit-object) seems to say otherwise.

Am I missing something? As this seems like a relatively straightforward implementation. Is there a better way to send the log message to a backend service? We don't necessarily need it as an array but it seems like the correct way to retrieve and send it. We may need to end up making a custom transport but wanted to be sure I wasn't missing anything simple.

Using webpack with default configuration. Node 8.9.x, Chrome latest. I can spin up a demo repo if needed.

Thanks for your time.
