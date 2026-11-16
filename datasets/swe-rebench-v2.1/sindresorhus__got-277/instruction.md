Add protocol to error messages
https://github.com/sindresorhus/got/blob/master/index.js#L339 has a bunch of request settings copied into the error object. The protocol would also be helpful.

### Additional contract requirements

The error object produced when a request fails exposes a `protocol` property whose value is the request protocol, including the trailing colon (for example `'http:'` or `'https:'`).
