Not handling correctly `request.url` being undefined
Starting with Hapi@18, all extensions on the`onRequest` event need to handle that [`request.url` might be undefined](https://github.com/hapijs/hapi/issues/3871).

> if you have onRequest extension handlers, make sure your code can handle request.url being set to null if the request.path received is invalid.

We recently had a problem with hapi-pino, because the `isLoggingIgnored` functions threw a type error.

```javascript
  function isLoggingIgnored (options, request) {
   // request.url can be undefined at this point;
[HIDDEN]
      return true
    }
```
