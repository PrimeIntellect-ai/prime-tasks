Returning `null` overrides status code
From https://github.com/unjs/ipx/issues/178 by @aaharu

```js
import { createServer } from 'node:http'
import { createApp, eventHandler, toNodeListener, setResponseStatus } from 'h3'

const app = createApp()
app.use(
  '/',
  eventHandler((event) => {
    setResponseStatus(event, 304)
    return null
  })
)

createServer(toNodeListener(app)).listen(process.env.PORT || 8000)
```

[HIDDEN]
