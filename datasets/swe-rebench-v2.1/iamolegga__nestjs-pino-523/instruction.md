[FEATURE REQUEST] Changing loglevel during runtime.
Is there any way to dynamically change `loglevel `during runtime? Like in pino using `logger.level`.

https://github.com/pinojs/pino/blob/master/docs/api.md#loggerlevel-string-gettersetter

It will be very useful in my case, when I want to change `loglevel `in working microservice without its reloading. Now I set it with `.env` and there is no way to change it dynamicly.

### Additional contract requirements

- The active log level of the application's logger must be changeable at runtime, without restarting or reloading the application.
- The root pino logger created by the module must be reachable as the static property `PinoLogger.root`, so that its `level` can be assigned at runtime (for example `PinoLogger.root.level = 'info'`). Requests handled after the change must log at the new level.
