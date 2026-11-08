Calling OPTIONS method causes error on server
Based on latest main code:
```
npm start
curl -i -X OPTIONS http://localhost:3000/
```
The server log reports:
```
2021-02-04T10:51:59.965Z [ExpressHttpServerFactory] error: Error: Cannot set headers after they are sent to the client
Error [ERR_HTTP_HEADERS_SENT]: Cannot set headers after they are sent to the client
    at ServerResponse.setHeader (_http_outgoing.js:558:11)
    at HeaderHandler.handle (/Users/pete/work/solid/community-server/dist/server/middleware/HeaderHandler.js:15:22)
    at /Users/pete/work/solid/community-server/dist/util/handlers/ParallelHandler.js:19:67
    at Array.map (<anonymous>)
    at ParallelHandler.handle (/Users/pete/work/solid/community-server/dist/util/handlers/ParallelHandler.js:19:42)
    at SequenceHandler.handle (/Users/pete/work/solid/community-server/dist/util/handlers/SequenceHandler.js:27:40)
    at runMicrotasks (<anonymous>)
    at processTicksAndRejections (internal/process/task_queues.js:93:5)
    at async /Users/pete/work/solid/community-server/dist/server/ExpressHttpServerFactory.js:24:17
```
The response seems OK:
```
HTTP/1.1 204 No Content
X-Powered-By: Express
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
Access-Control-Allow-Methods: GET,HEAD,OPTIONS,POST,PUT,PATCH,DELETE
Vary: Access-Control-Request-Headers
Access-Control-Expose-Headers: Accept-Patch,Location,MS-Author-Via,Updates-Via
Content-Length: 0
Date: Thu, 04 Feb 2021 10:51:59 GMT
Connection: keep-alive
Keep-Alive: timeout=5
```

### Additional contract requirements

- For an OPTIONS request, the response must include `Updates-Via: wss://example.pod/` and `X-Powered-By: Community Solid Server`. Its `Vary` header must include `Accept`, `Authorization`, and `Origin`.
