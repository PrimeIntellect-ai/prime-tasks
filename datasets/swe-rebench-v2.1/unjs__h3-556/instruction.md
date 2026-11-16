Support optional decoding for `getRouterParam`
### Environment

Node: 18.18.0

### Reproduction

```ts
import { createApp, eventHandler, createRouter } from "h3";

const app = createApp();

const router = createRouter()

router.get(
  '/:name',
  eventHandler((event) => `Hello ${event.context.params.name}!`)
);

app.use(router);
```


### Describe the bug

Expected: **Hello something with test!**
But got: **Hello something%20with%20test!**

param is not being decoded here.

### Additional context

_No response_

### Logs

_No response_

### Additional contract requirements

`getRouterParam(event, name, { decode: true })` returns the named route parameter after URL decoding it.
