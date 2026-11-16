Error: "fn is not a function" while setting up a pino transports since v9.2.1
Pino `v9.3.0` throws errors

```
#10 23.21 5e4f8d756c2d9898b115a52167c82923990c1c73 (Node v20.11.1)
#10 23.22 node:events:496
#10 23.22       throw er; // Unhandled 'error' event
#10 23.22       ^
#10 23.22
#10 23.22 TypeError: fn is not a function
#10 23.22     at /snapshot/dist/pino-worker.js:10
#10 23.22     at process.processTicksAndRejections (node:internal/process/task_queues:95:5)
#10 23.22     at async Promise.all (index 0)
#10 23.22     at async module.exports (/snapshot/dist/pino-worker.js:10713:15)
#10 23.22     at async start (/snapshot/dist/thread-stream-worker.js:134:17)
#10 23.22 Emitted 'error' event on ThreadStream instance at:
#10 23.22     at Immediate.<anonymous> (/snapshot/dist/containerbase-cli.js:6481:17)
#10 23.22     at process.processImmediate (node:internal/timers:4
```

Update PR
- https://github.com/containerbase/base/pull/2942

Logger init code
- https://github.com/containerbase/base/blob/main/src/cli/utils/logger.ts

The code will be transpiled with `esbuild` and then packaged with `@yao-pkg/pkg`
- https://github.com/containerbase/base/blob/main/tools/esbuild.js

Seems to be related to #1383
