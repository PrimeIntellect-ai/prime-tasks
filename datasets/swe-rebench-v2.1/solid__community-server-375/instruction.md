Default server leaves dangling locks on PATCH
Below are the logs of the default server receiving a `PATCH` on any path.

```
$ npm start

> @solid/community-server@0.2.0 start /Users/ruben/Documents/UGent/Solid/solid-community-server
> node ./bin/server.js -p 3000

2020-11-29T09:55:11.934Z [CliRunner] info: Running at http://localhost:3000/
2020-11-29T09:55:13.027Z [ExpressHttpServerFactory] info: Received request for /
2020-11-29T09:55:13.044Z [RepresentationConvertingStore] info: Convert http://localhost:3000/.acl from text/turtle to internal/quads;q=1
2020-11-29T09:55:13.047Z [WebAclAuthorizer] info: Reading ACL statements from http://localhost:3000/.acl
2020-11-29T09:55:13.053Z [RepresentationConvertingStore] info: Convert http://localhost:3000/ from internal/quads to text/turtle;q=1
2020-11-29T09:55:16.057Z [WrappedExpiringLock] warn: Lock expired after 3000ms
```

Since this went undetected, I have bumped the log level of lock expiry, which should be a rare event: 1d08f463f692ac4f44c781d101176aa4ec36ac2e
