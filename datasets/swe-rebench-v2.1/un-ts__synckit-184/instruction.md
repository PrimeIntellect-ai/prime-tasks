`syncFn` timeout causes subsequent calls to fail.
Whenever there is a long-running function executed in the worker and it's execution time exceeds the timeout configured in `createSyncFn`, the function execution isn't stopped. This means that when it finally finishes and sends the message with response, subsequent calls to the worker will result in this error: `Error: Internal error: Expected id X but got id Y` because always an older message is waiting in the parent message channel queue.

I have prepared this example code:

```javascript
const { runAsWorker, createSyncFn } = require('synckit');
const { isMainThread } = require('worker_threads');

if (isMainThread) {
    const TIMEOUT = 1000;
    const executeSyncTimeout = createSyncFn(__filename, { timeout: TIMEOUT });

    const sleep = (time) => {
        try {
            console.log('sleeping for ' + time);
            executeSyncTimeout(time);
        } catch (e) {
            console.log(e);
        }
    };

    sleep(TIMEOUT / 2); // id = 0; success because shorter than timeout
    sleep(TIMEOUT * 2); // id = 1; task is longer than timeout -> error in parent thread, but task continues in worker
    sleep(TIMEOUT / 2); // id = 2; success because shorter than timeout and long task in worker hasn't finished yet
    sleep(TIMEOUT / 2); // id = 3; error because long task in worker (id 1) finished and sent it's message to parent
    sleep(TIMEOUT / 2); // id = 4; error because message from task id 3 is still in message queue
    sleep(TIMEOUT / 2); // id = 5; error because message from task id 4 is still in message queue
} else {
    runAsWorker(async (sleepTime) => {
        await new Promise((resolve) => {
            setTimeout(resolve, sleepTime);
        });
    });
}

```

which results in these logs being printed:
```
sleeping for 500
sleeping for 2000
Error: Internal error: Atomics.wait() failed: timed-out
sleeping for 500
sleeping for 500
Error: Internal error: Expected id 3 but got id 1
sleeping for 500
Error: Internal error: Expected id 4 but got id 3
sleeping for 500
Error: Internal error: Expected id 5 but got id 4
```

### Additional contract requirements

- An outdated response (a response whose `id` is lower than the `id` of the call currently waiting for its result) must be discarded so that the waiting call can receive its own response. Outdated responses must not cause the waiting call, or any subsequent call, to fail.
- A response whose `id` is not the expected `id` and is not outdated (for example, a response with a greater `id`) must still raise `Error: Internal error: Expected id X but got id Y`.
