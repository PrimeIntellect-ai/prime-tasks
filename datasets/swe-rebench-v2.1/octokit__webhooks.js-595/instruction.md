`signature does not match event payload and secret` when receiving JSON body
<!-- Please replace all placeholders such as this below -->

**What happened?**

After updating `@octokit/webhooks` from v9.5.1 to v9.8.2, I now receive this error on all webhook events

```
AggregateError:
2021-06-19T02:53:43.735393200Z     Error: [@octokit/webhooks] signature does not match event payload and secret
2021-06-19T02:53:43.735470900Z         at verifyAndReceive (/usr/src/app/node_modules/@octokit/webhooks/dist-src/verify-and-receive.js:9:23)
2021-06-19T02:53:43.735505400Z         at middleware (/usr/src/app/node_modules/@octokit/webhooks/dist-src/middleware/node/middleware.js:39:9)
2021-06-19T02:53:43.735535200Z     at receive (/usr/src/app/node_modules/@octokit/webhooks/dist-src/event-handler/receive.js:15:37)
2021-06-19T02:53:43.735560400Z     at verifyAndReceive (/usr/src/app/node_modules/@octokit/webhooks/dist-src/verify-and-receive.js:10:35)
2021-06-19T02:53:43.735587700Z     at processTicksAndRejections (internal/process/task_queues.js:95:5)
2021-06-19T02:53:43.735621500Z     at middleware (/usr/src/app/node_modules/@octokit/webhooks/dist-src/middleware/node/middleware.js:39:9) {
2021-06-19T02:53:43.735656300Z   event: Error: [@octokit/webhooks] signature does not match event payload and secret
2021-06-19T02:53:43.735774200Z       at verifyAndReceive (/usr/src/app/node_modules/@octokit/webhooks/dist-src/verify-and-receive.js:9:23)
2021-06-19T02:53:43.736161500Z       at processTicksAndRejections (internal/process/task_queues.js:95:5)
2021-06-19T02:53:43.736196500Z       at middleware (/usr/src/app/node_modules/@octokit/webhooks/dist-src/middleware/node/middleware.js:39:9) {
2021-06-19T02:53:43.736222800Z     event: {
2021-06-19T02:53:43.736245700Z       id: '8f2b4480-d0a9-11eb-901c-fd8bfc9148cf',
2021-06-19T02:53:43.736268800Z       name: 'issues',
2021-06-19T02:53:43.736298100Z       payload: [Object],
2021-06-19T02:53:43.736336100Z       signature: 'sha256=7fd7cab774ec3308791747ec253ec258e0add40ece88bc565035de0b48690448'
2021-06-19T02:53:43.736362700Z     },
2021-06-19T02:53:43.736449500Z     status: 400
2021-06-19T02:53:43.736496500Z   },
2021-06-19T02:53:43.736775800Z   errors: [
2021-06-19T02:53:43.736883300Z     Error: [@octokit/webhooks] signature does not match event payload and secret
2021-06-19T02:53:43.736914200Z         at verifyAndReceive (/usr/src/app/node_modules/@octokit/webhooks/dist-src/verify-and-receive.js:9:23)
2021-06-19T02:53:43.736945900Z         at processTicksAndRejections (internal/process/task_queues.js:95:5)
2021-06-19T02:53:43.736972800Z         at middleware (/usr/src/app/node_modules/@octokit/webhooks/dist-src/middleware/node/middleware.js:39:9) {
2021-06-19T02:53:43.737002700Z       event: [Object],
2021-06-19T02:53:43.737031400Z       status: 400
2021-06-19T02:53:43.737110800Z     }
2021-06-19T02:53:43.737136200Z   ]
2021-06-19T02:53:43.737160300Z }
2021-06-19T02:53:43.772597000Z POST /api/webhooks/github 400 56.694 ms - -
```

I am using the Express framework with the following middleware

```js
app.use((req, res, next) => {
  if (req.originalUrl.includes('/stripe/webhook')) {
    bodyParser.raw({ type: 'application/json' })(req, res, next);
  } else {
    bodyParser.json()(req, res, next);
  }
});
```

**What did you expect to happen?**

For it to work as expected, and not be a breaking change.

**What the problem might be**

The problem is https://github.com/octokit/webhooks.js/pull/587, which updated to the breaking change in `@octokit/webhooks-methods`, and seemingly added a compatibility layer, however that seems to have had no effect for my set up, resulting in the breaking change persisting.

Changing the middleware to be this works:
```js
app.use((req, res, next) => {
  if (req.originalUrl.includes('/stripe/webhook')) {
    bodyParser.raw({ type: 'application/json' })(req, res, next);
  } else if (req.originalUrl.includes('/webhooks/github')) {
    bodyParser.text({ type: 'application/json' })(req, res, next);
  } else {
    bodyParser.json()(req, res, next);
  }
})
```
