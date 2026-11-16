Question | Hapi Pino Decorates Server Object with Logger as a Function
Had a quick question as to the reason the `logger` is decorated onto the server as a function returning the logger vs. just decorating the server object with the logger instance itself. However, the logger object on the `request` is not a function.

Example (feature request):
```
[HIDDEN]
```

https://github.com/pinojs/hapi-pino/blob/2d57bb6f0b186fa8212f84dc42e91ab2b8f95d8a/index.js#L83

In our microservices we heavily use the decorate method on the server object for a few different  things but haven't had a case where we needed to use it as a method returning what we want.

We may be missing something here so if it was intended I would love to know the explanation so we can potentially refactor some of our plugins to do so in this way. Otherwise it would be nice to not have to return the logger as a function

### Additional contract requirements

- The server's `logger` decoration must expose the logger instance directly as a property, not as a function returning it; callers can use its logging methods through `server.logger`.
