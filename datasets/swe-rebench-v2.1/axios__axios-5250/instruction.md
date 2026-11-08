Z_BUF_ERROR when content-encoding is set but the response body is empty
### Describe the bug

I get a `Z_BUF_ERROR` when requesting an endpoint that sets the `content-encoding` but does not return any response body.  See the snippet for server and client.

The error
```
AxiosError: unexpected end of file
    at Function.AxiosError.from (/Users/joona.paakkonen/git/test-server/node_modules/axios/dist/node/axios.cjs:725:14)
    at Unzip.handleStreamError (/Users/joona.paakkonen/git/test-server/node_modules/axios/dist/node/axios.cjs:2430:29)
    at Unzip.emit (node:events:532:35)
    at emitErrorNT (node:internal/streams/destroy:157:8)
    at emitErrorCloseNT (node:internal/streams/destroy:122:3)
    at processTicksAndRejections (node:internal/process/task_queues:83:21)
```

I checked that the logic [here](https://github.com/lejahmie/axios/blob/master/lib/adapters/http.js#L275) does not seem to make much sense, the `data` is not the response data but rather the request data. And we don't seem to have request data available since it's still left to be streamed. Perhaps the decompression should happen after the response has been received. The old logic where `HTTP 204` response code was used to make the decision was probably better.

### To Reproduce

Test server
```
const express = require('express');
const compression = require('compression');
const app = express();
const port = 3000;

app.use(express.json())
app.use(compression({ threshold: 0 }));

app.get('/success-1', (request, response) => {
  response.end();
});

app.get('/success-2', (request, response) => {
  response.json({foo: 'bar'});
  response.end();
});

app.get('/fail-1', (request, response) => {
  response.setHeader('content-encoding', 'gzip');
  response.end();
});

const server = app.listen(port, () => {
  console.log(`Listening at http://localhost:${port}`);
});
```

Test client
```
const axios = require('axios');
const PATHS = ['success-1', 'success-2', 'fail-1'];

(async () => {
  for (const path of PATHS) {
    try {
      const response = await axios.request({
        method: 'GET',
        url: `http://localhost:3000/${path}`,
      });
      console.log(path, response.data, 'SUCCESS!');
    } catch (error) {
      console.log(path, 'FAIL!');
    }
  }
})();
```

### Code snippet

_No response_

### Expected behavior

I would expect axios request to not fail when even when the response body is missing. This was the behaviour for 0.27.2

### Axios Version

1.1.3

### Adapter Version

XHR/HTTP

### Browser

_No response_

### Browser Version

_No response_

### Node.js Version

v16.14.0

### OS

OSX

### Additional Library Versions

_No response_

### Additional context/Screenshots

_No response_
