Non status-code 200 responses in result structure
With latest node.js API version 0.9.0, the use of the result structure has changed.  Non status-code 200 responses are not being reported back in the 'err' parameter of the callback.
Can you please advise on checks that should be done.  The code examples seem to be insufficient, such as https://github.com/SparkPost/node-sparkpost/blob/master/examples/transmissions/stored_template_send.js

### Additional contract requirements

An HTTP response with a 4xx or 5xx status is a failure and must be reported through the callback's first argument (`err`), rather than as a successful response. A successful HTTP 2xx response, including status 200, must not be reported as an error.
