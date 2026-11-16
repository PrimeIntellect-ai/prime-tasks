It cannot be used with pipeline()
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the bug has not already been reported


### Fastify version

unknown

### Plugin version

unknown

### Node.js version

v16.16.0

### Operating system

macOS

### Operating system version (i.e. 20.04, 11.3, 10)

unknown

### Description

Under Node.js 16 ( v16.16.0 ), inject() cannot be used with pipeline() at the same time.

Under Node.js 14 ( v14.20.0 ), it works.

### Steps to Reproduce

1. Code.

```js
const { pipeline } = require("stream");

const { inject } = require("light-my-request");

(async () => {
  const resp = await inject((req, res) => {
    const data = `
  <!DOCTYPE html>
  <html>

    <head>
      <meta charset="UTF-8">
      <title>Document</title>
    </head>

    <body>
      <p>basic:ejs</p>
    </body>

  </html>
  `;

    res.statusCode = 200;

    pipeline(data, res, () => res.end());
  })
    .get("/")
    .end();

  console.log(resp.body);
})();
```

2. Run it.

```sh
  <!DOCTYPE html>
  <html>

    <head>
      <meta charset="UTF-8">
      <title>Document</title>
    </head>

    <body>
      <p>basic:ejs</p>
    </body>

  </html>

node:internal/streams/end-of-stream:206
    if (stream.req) stream.req.removeListener('finish', onfinish);
                               ^

TypeError: stream.req.removeListener is not a function
    at cleanup (node:internal/streams/end-of-stream:206:32)
    at pump (node:internal/streams/pipeline:166:5)
    at processTicksAndRejections (node:internal/process/task_queues:96:5)
```


### Expected Behavior

_No response_

### Additional contract requirements

On Node.js 16, an injected response can be used with `stream.pipeline()` without the reported `TypeError`. Data sent through the pipeline is returned in the injection response payload.
