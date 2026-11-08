Modify sendingDomains.verify to use standard two argument pattern
Verify currently accepts three arguments. We have changed our pattern to take a max of two. Need to switch to taking an options object and a callback function.

### Additional contract requirements

- Add a public method `sendingDomains.verify(options, callback)` in `lib/sendingDomains.js` (inside the exported `sendingDomains` object).
- `options` is an object with a required `domainName` string, used to build the request URI `sending-domains/<domainName>/verify`.
- `options.verifyDKIM` and `options.verifySPF` are optional booleans that default to `true`; the request body is `{ dkim_verify: <boolean>, spf_verify: <boolean> }`.
- `callback` is a function `function(err, response)` invoked after the HTTP request completes.
- If `options` is null or does not contain a `domainName`, the callback is invoked with `Error('domainName is required')` and no HTTP request is made.
