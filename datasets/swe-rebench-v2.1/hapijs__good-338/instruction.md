bug when filter is used
I'm getting the following error for GET requests when applying a filter:
```
Debug: internal, implementation, error
    TypeError: Cannot read property 'key' of undefined
    at Object.<anonymous> (/Users/damirv/hapi/node_modules/good/lib/utils.js:93:69)
    at walker (/Users/damirv/hapi/node_modules/good/node_modules/traverse/index.js:190:22)
    at walk (/Users/damirv/hapi/node_modules/good/node_modules/traverse/index.js:226:7)
    at Traverse.forEach (/Users/damirv/hapi/node_modules/good/node_modules/traverse/index.js:50:18)
    at applyFilter (/Users/damirv/hapi/node_modules/good/lib/utils.js:90:24)
    at new exports.GreatResponse (/Users/damirv/hapi/node_modules/good/lib/utils.js:146:9)
    at Object.exports.GreatResponse (/Users/damirv/hapi/node_modules/good/lib/utils.js:77:16)
    at internals.Monitor._responseHandler (/Users/damirv/hapi/node_modules/good/lib/monitor.js:230:33)
    at emit (events.js:95:17)
    at handler (/Users/damirv/hapi/node_modules/hapi/node_modules/kilt/lib/index.js:54:44)
```

I've set up a sample app that shows this problem: https://github.com/damirv/hapi-good-filter-bug.

Am I missing something or this a bug? It seems that [applyFilter](https://github.com/hapijs/good/blob/master/lib/utils.js#L88) is being passed null for `data`.
