Got throws an error instead of redirecting for 303, 307 or 308
```javascript
{ HTTPError: Response code 308 (Permanent Redirect)
    at EventEmitter.ee.on.res (/home/user/Desktop/REPOS/transfer-sh/node_modules/got/index.js:182:24)
    at emitOne (events.js:96:13)
    at EventEmitter.emit (events.js:188:7)
    at Immediate.setImmediate (/home/user/Desktop/REPOS/transfer-sh/node_modules/got/index.js:61:8)
    at tryOnImmediate (timers.js:543:15)
    at processImmediate [as _immediateCallback] (timers.js:523:5)
  message: 'Response code 308 (Permanent Redirect)',
  host: 'transfer.sh',
  hostname: 'transfer.sh',
  method: 'PUT',
  path: '/README.md',
  statusCode: 308,
  statusMessage: 'Permanent Redirect' }
```

Redirect not followed?

### Additional contract requirements

- When a 303 redirect is followed, the returned response's `url` must be the URL in the `Location` header.
