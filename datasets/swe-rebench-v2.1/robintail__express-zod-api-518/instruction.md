Middlewares do not run for the OPTIONS request
Doing `.addExpressMiddleware(cors())` has no effect since it's not run for the OPTIONS request. This example is also in Readme, so it should be fixed.

_Originally posted by @HardCoreQual in https://github.com/RobinTail/express-zod-api/discussions/500#discussioncomment-3186884_

> Can be bug that
`ExpressZodEndpoidFactory.addExpressMiddleware(cors()) `  don't  work         // createServer
and is necessary to use `expressApp.use(cors())`                                               // attachRouting
or it work like expected ?

### Additional contract requirements

- For an OPTIONS request, the endpoint must respond with status 200.
