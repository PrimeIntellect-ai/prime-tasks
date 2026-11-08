Cannot read property 'info' of undefined
I have been getting this error whenever I refresh my Apollo graphql playground and based on the error trace `request.logger` inside `tryAddEvent` function (request completes ) is undefined
```log
TypeError: Cannot read property 'info' of undefined
    at Object.listener (/home/akumzy/momo/planner-server/node_modules/hapi-pino/index.js:120:25)
    at module.exports.internals.Podium.internals.Podium.emit (/home/akumzy/momo/planner-server/node_modules/@hapi/podium/lib/index.js:224:107)
    at Request._finalize (/home/akumzy/momo/planner-server/node_modules/@hapi/hapi/lib/request.js:447:27)
    at Request._reply (/home/akumzy/momo/planner-server/node_modules/@hapi/hapi/lib/request.js:391:14)
    at processTicksAndRejections (internal/process/task_queues.js:85:5)
error Command failed with exit code 1.
info Visit https://yarnpkg.com/en/docs/cli/run for documentation about this command.
```
