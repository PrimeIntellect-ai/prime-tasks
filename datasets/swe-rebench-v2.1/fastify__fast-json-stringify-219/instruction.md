date field serialization crashes when null
## 🐛 Bug Report

I have a timestamp field in my schema named 'updatedAt' and defined as follows:

```js
{
  updatedAt: { type: ['string', null], format: 'date-time'}
}
```

When a record is created for the first time, the ORM return updatedAt with null, because only createdAt is set on record creation.

When it goes through serialization, I get the following error:

```
TypeError: Cannot read property 'toISOString' of null
     at $asDatetime (eval at build (/usr/src/app/node_modules/fast-json-stringify/index.js:142:20), <anonymous>:60:26)
     at $arr$mainusermembershipsi (eval at build (/usr/src/app/node_modules/fast-json-stringify/index.js:142:20), <anonymous>:554:17)
     at $arr$mainusermemberships (eval at build (/usr/src/app/node_modules/fast-json-stringify/index.js:142:20), <anonymous>:452:17)
     at $mainuser (eval at build (/usr/src/app/node_modules/fast-json-stringify/index.js:142:20), <anonymous>:403:17)
     at Object.$main (eval at build (/usr/src/app/node_modules/fast-json-stringify/index.js:142:20), <anonymous>:134:17)
     at serialize (/usr/src/app/node_modules/fastify/lib/validation.js:132:41)
     at preserializeHookEnd (/usr/src/app/node_modules/fastify/lib/reply.js:298:15)
    at next (/usr/src/app/node_modules/fastify/lib/hooks.js:101:7)
     at handleResolve (/usr/src/app/node_modules/fastify/lib/hooks.js:112:5)
     at process._tickCallback (internal/process/next_tick.js:68:7)
```

## To Reproduce

Steps to reproduce the behavior:


The generated eval code strictly checks for underfined, so null is considered a valid value! Here's is what the generated code looks like:
```js
[HIDDEN]
```
And since the function below doesn't check for `null`,  the second condition `date.toISOString ` triggers the error `Cannot read property 'toISOString'` because `date` itself is null!
 ```js
[HIDDEN]
```

My suggestion is to make 2 changes as proposed below:
```js
[HIDDEN]
```

## Your Environment

- *node version*: 10
- *fastify version*: 2.13.0
- *os*: Mac and alpine (dockerized)

### Additional contract requirements

- When `updatedAt` is `null` and its schema has `type: 'string'` or `type: ['string']` with `format: 'date-time'`, `format: 'date'`, or `format: 'time'`, serialization must produce `{"updatedAt":""}`.
- When the schema permits `null` and has one of those formats, serializing a `null` `updatedAt` must produce `{"updatedAt":null}`.
