logger.setBindings() doesn't clear logger[Symbol(pino.parsedChindings)]
#754 added a very useful `logger.setBindings()` method. But this doesn't play well with prettifiers, which appear to make use of a cached version of the bindings:

```js
> let child=logger.child({foo: 123});

// pino.parsedChindings is undefined at start
> child.bindings()
{ foo: 123 }
> child[Pino.symbols.parsedChindingsSym]
undefined

// when the first log call is made, pino.parsedChindings gets populated
> child.info('hello')
[2020-08-11 23:12:27.349 +0000] INFO : hello
    foo: 123
> child[Pino.symbols.parsedChindingsSym]
{ pid: 16561, hostname: 'nutrimatic', foo: 123 }

// logger.setBindings doesn't update pino.parsedChindings
> child.setBindings({bar: 456})
> child.bindings()
{ foo: 123, bar: 456 }
> child[Pino.symbols.parsedChindingsSym]
{ pid: 16561, hostname: 'nutrimatic', foo: 123 }

// so subsequent logs don't include the new bindings
> child.info('hello')
[2020-08-11 23:13:24.553 +0000] INFO : hello
    foo: 123
> child[Pino.symbols.parsedChindingsSym]
{ pid: 16561, hostname: 'nutrimatic', foo: 123 }

// manually clearing pino.parsedChindings causes it to be regenerated on the next log call
> delete child[Pino.symbols.parsedChindingsSym]
> child.info('hello')
[2020-08-11 23:14:28.240 +0000] INFO : hello
    foo: 123
    bar: 456
> child[Pino.symbols.parsedChindingsSym]
{ pid: 16561, hostname: 'nutrimatic', foo: 123, bar: 456 }
```

[HIDDEN]

I can submit a PR for either of these approaches; I'm just not sure which is best.

### Additional contract requirements

When bindings are changed on a logger with pretty printing enabled, a subsequent log must show the effective bindings, including values added or retained by the update. This may happen automatically after `setBindings`; alternatively, the logger may expose a public `invalidateBindings()` method that callers can invoke after `setBindings` and before logging. If provided, `invalidateBindings()` takes no arguments.
