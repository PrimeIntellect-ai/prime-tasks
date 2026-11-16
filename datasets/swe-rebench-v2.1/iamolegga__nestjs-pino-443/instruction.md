[FEATURE REQUEST] make the underlying pino instance accessible
**Is your feature request related to a problem? Please describe.**
The underlying [pino instance is private](https://github.com/iamolegga/nestjs-pino/blob/99247e6c64732689c5de8b8dabcaa311bf95c632/src/PinoLogger.ts#L110-L112).

**Describe the solution you'd like**
[HIDDEN]

**Describe alternatives you've considered**
Creating a separate pino instance to pass down to the parts of the system that need a `Logger` would be an alternative. This would make it quite a lot more complicated though.

**Additional context**
Some of the business logic in our projects is generic in a way that it does not know about NestJS specifics, but knows about pino (especially its `child()` method). These are given a pino logger from the NestJS specific parts (e.g. controllers). If we do not use the private getter that is linked above, we would need to maintain a separate second pino instance, hence, not gaining anything from using such a sweet package as `nestjs-pino`.

### Additional contract requirements

- Consumers must be able to access the same underlying Pino logger instance used by `PinoLogger` and use it as a native Pino logger, including calling `child()`.
- The underlying logger must be readable as a public property of `PinoLogger` instances, so code outside the class can reach it without subclassing.
