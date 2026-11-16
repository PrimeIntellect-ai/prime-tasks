obj.hasOwnProperty is not a function
Found this deep inside our server logs

```
obj.hasOwnProperty is not a function
    at EventEmitter.asJson (/Users/ronagy/Projects/github/nxtedition/nxt-storage/node_modules/pino/pino.js:175:15)
    at EventEmitter.Pino.write (/Users/ronagy/Projects/github/nxtedition/nxt-storage/node_modules/pino/pino.js:224:16)
    at EventEmitter.LOG (/Users/ronagy/Projects/github/nxtedition/nxt-storage/node_modules/pino/lib/tools.js:116:10)
```

Not sure how to reproduce it.

### Additional contract requirements

- Logging an object with a null prototype should not throw and should serialize its own enumerable fields.
