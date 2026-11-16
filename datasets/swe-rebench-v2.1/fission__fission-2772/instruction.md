Fission buffers server-sent event requests until they are complete before streaming the response
**Fission/Kubernetes version**

Fission 1.17.11
K8S 1.26
Kubernetes platform: docker-desktop

**Describe the bug**

When running a serverless function which pushes a response slowly over time (on purpose), fission appears to buffer the whole result, and only send it to the client once the response is complete. This slow sending is useful for [server-sent events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events) (SSE), a common way of streaming a slow computation to the client as it is ready on the server.

Notably, OpenAI's APIs use SSE to stream chat responses from LLMs, so any developers wanting to use LLMs in their fission-based apps will consume SSE, and likely want to provide a good user experience by returning SSE to the client.

**To Reproduce**

We're using a custom nodejs environment that controls the HTTP response directly instead of using the `fission/node-env` environment, so we're able to write raw buffers to the response. Within `fission/node-env`, it's kind of hard. Reading the node-env code, I think you can dodge it's response sending by just returning `{}` from your handler function, and then sending the response later, but that's kind of cheating. In any case, here's a low-level nodejs server with no dependencies which streams a response using server-sent events:

```javascript
// Import the built-in http module
const http = require('http');

// Create an HTTP server
const server = http.createServer((req, res) => {
    // Set the appropriate headers for server-sent events
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders();

    let sentTimes = 0;

    // Send the current time every 500 ms
    const interval = setInterval(() => {
      // Increment the sentTimes counter
      sentTimes++;

      // Send the current time as an SSE
      res.write(`data: ${new Date().toISOString()}\n\n`);

      // If we've sent the time 10 times, close the connection and clear the interval
      if (sentTimes >= 10) {
        clearInterval(interval);
        res.end();
      }
    }, 500);
});

// Start the server on port 3000
server.listen(3000, () => {
  console.log('Server running on http://localhost:3000');
});
```

**Expected result**

Fission relays each chunk of the response to the caller as it arrives, without buffering.

**Actual result**

Fission buffers the whole response, and only sends it once complete.

**Additional context**

My suspicion is that something inside the fission router accidentally buffers the response. I took a look at the `httputil` proxy code and nothing immediately stood out to me, but I am not a great golang programmer. Perhaps you folks know what this might be! SSE support would be really great to get!
