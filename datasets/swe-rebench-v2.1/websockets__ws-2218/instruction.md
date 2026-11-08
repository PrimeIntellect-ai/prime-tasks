Messages are dispatched while microtask queue is not empty
### Is there an existing issue for this?

- [X] I've searched for any related issues and avoided creating a duplicate issue.

### Description

I have previously reported https://github.com/websockets/ws/issues/2159 which was fixed but it looks like the solution might not have been complete.

With the latest version of ws the microtasks scheduled in the event callback are handled first but the microtasks created by those microtasks are not. This is different from the WebSocket client behavior in the browser.

Server code:

```js
import { WebSocketServer } from 'ws';

const wss = new WebSocketServer({ port: 8080 });

wss.on('connection', function connection(ws) {
  ws.send('something1');
  ws.send('something2');
});
```

Client code:

```
import { WebSocket } from 'ws';

const ws = new WebSocket('ws://127.0.0.1:8080');

ws.addEventListener('message', function message(event) {
    console.log('received: %s', event.data);
    new Promise(resolve => {
      resolve()
    }).then(() => {
      console.log('microtask', event.data.toString())
      return Promise.resolve().then(() => {
        console.log('microtask-nested', event.data.toString());
      });
    })
});
```

### ws version

8.16.0

### Node.js Version

v20.10.0

### System

  System:
    OS: macOS 14.4.1
    CPU: (10) arm64 Apple M1 Max
    Memory: 12.88 GB / 64.00 GB
    Shell: 5.9 - /bin/zsh

### Expected result

```
received: something1
microtask something1
microtask-nested something1
received: something2
microtask something2
microtask-nested something2
```

### Actual result

```
received: something1
microtask something1
received: something2
microtask-nested something1
microtask something2
microtask-nested something2
```


### Attachments

_No response_
