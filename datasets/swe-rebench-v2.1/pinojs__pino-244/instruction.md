Invalid time value with prettyPrint and timestamp:false
> node app.js | pino

```
/myp/node_modules/pino/pretty.js:130
    return new Date(time).toISOString()

RangeError: Invalid time value
```

This happens when you set `prettyPrint` true (or pipe the output to pino without timestamps)
