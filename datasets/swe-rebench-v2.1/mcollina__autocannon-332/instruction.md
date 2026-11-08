client.setHeaders only sets headers for first request
I'm not sure if this is intended behavior or a bug, but in the `setupClient`, while doing a `client.setHeaders`, it only affects the first request in the `requests` array.

Example:


```js
'use strict'

const autocannon = require('autocannon')

autocannon({
    url: `https://example.com`,
    connections: 1,
    duration: 1,
    amount: 1,
    setupClient: (client) => {
        const userInfo = getNextUserInfo()
        // I expect this to set the headers for all requests in the list below
        client.setHeaders({
            'Authorization': userInfo.authorizationToken,
            'Content-Type': 'application/json',
        })
    },
    requests: [
        {
            path: `/someEndpoint`,
            method: 'POST',
            setupRequest: (req, context) => {
                // I do this hack to get the headers forwarded to the next request;
                // context.authHeaders = req.headers // left out to show bug
                return {
                    ...req,
                    body: JSON.stringify({
                        command: 'startTournamentLevel',
                    }),
                }
            },
            onResponse: (status, body, context) => {
                if (status === 200) {
                    context.data = JSON.parse(body)
                }
            },
        },
        {
            path: `/someOtherEndpoint`,
            method: 'POST',
            setupRequest: (req, context) => {
                console.log('req.headers is not set', JSON.stringify(req.headers))
                return {
                    ...req,
                    // headers: context.authHeaders, // I do this hack to get the headers forwarded. Left out to expose bug
                    body: JSON.stringify({
                        someData: context.data.some,
                    }),
                }
            },
        }],
}, console.log)
```

I think I have found the reason in the source code;

[HIDDEN]

[HIDDEN]

Again, not sure if it is a bug, but it feels like it. I was able to work around it by adding the headers to the context object on the first request, in case anyone else has this issue.

### Additional contract requirements

- Headers supplied through `client.setHeaders` during `setupClient` must be sent with every request in the configured request sequence, not just the first request.
