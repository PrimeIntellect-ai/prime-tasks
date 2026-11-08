logEvent.messages contains child bindings after first call of transmit.send
**Description**

Given the following code:

```js
import pino from "pino";

const root = document.getElementById("root");
const logger = pino({
  browser: {
    transmit: {
      send(_, logEvent) {
        const messages = document.createElement("pre");
        messages.innerHTML = JSON.stringify(logEvent.messages);
        const bindings = document.createElement("pre");
        bindings.innerHTML = JSON.stringify(logEvent.bindings);
        root.appendChild(messages);
        root.appendChild(bindings);
        root.appendChild(document.createElement("hr"));
      }
    }
  }
}).child({ foo: "bar" });

logger.info("hello");
logger.info("world");
logger.info("how are you");
```

For the first call of `logger.info`:
- `logEvent.messages` is `["hello"]`
- `logEvent.bindings` is `[{"foo":"bar"}]`

For the second call of `logger.info`:
- `logEvent.messages` is `[{"foo":"bar"},"world"]`
- `logEvent.bindings` is `[]`

Third call has same buggy output as second one.

**Reproduction**

https://codesandbox.io/s/ol3y3xy886

**Versions**
- pino@5.10.6
