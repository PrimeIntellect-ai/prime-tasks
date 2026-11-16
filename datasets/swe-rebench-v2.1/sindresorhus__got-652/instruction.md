Intermittent uncaught errors
With got version 9.2.2, I'm seeing `timed-out` crash occasionally with an unhandled `error` event. I'm using the promise API, not the stream-based one, so I expect this event to always be turned into a promise rejection.

```
TimeoutError: Timeout awaiting 'response' for 2000ms
  at Immediate.timeoutHandler (/node_modules/got/source/timed-out.js:39:25)
```
