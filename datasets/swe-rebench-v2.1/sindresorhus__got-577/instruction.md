Cannot use custom agent with got.extend()
Hi,

Because of unfortunate [deepFreeze of defaults](https://github.com/sindresorhus/got/blob/b8a086f8da53d57fdf11ba49eefa01d778a4f69f/source/create.js#L62) I cannot longer use any agent defined in the way like:

```javascript
const agents = require("./keepalive");
const got = require("got");

const request = exports.request = got.extend({
  timeout: 4000,
  agent: {
    http: agents.httpAgent,
    https: agents.httpsAgent
  }
});
```

This code will always break with error like `Cannot add property localhost:8080:, object is not extensible` as internal structures of agent object are also freezed. I do not want to set it per request as it is the main reason of `got.extend` existence...
