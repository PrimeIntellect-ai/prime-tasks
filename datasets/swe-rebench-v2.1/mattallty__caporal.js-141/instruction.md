Error setting up completion in bash
I get the following error when I try to setup auto completion in bash (macOS 10.14):

```
$ source <([app name] completion bash)
$ Error: write EPIPE
    at WriteWrap.afterWrite [as oncomplete] (net.js:788:14)
Emitted 'error' event at:
    at onwriteError (_stream_writable.js:431:12)
    at onwrite (_stream_writable.js:456:5)
    at _destroy (internal/streams/destroy.js:40:7)
    at Socket.dummyDestroy [as _destroy] (internal/process/stdio.js:11:34)
    at Socket.destroy (internal/streams/destroy.js:32:8)
    at WriteWrap.afterWrite [as oncomplete] (net.js:790:10)
```

This happens with my own cli and with the example cli.

For recreating with the example app;
1. `cd` to `examples/pizza`
2. run `npm install`
3. run `npm link`
4. run `fly` to confirm the command is installed
5. run `source <(fly completion bash)`. This is when the error is thrown

### Additional contract requirements

- When completing a positional argument that has static choices, the returned suggestions must be filtered to those that start with the partially-typed value (`lastPartial`).
