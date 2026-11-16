No-throw mode for `scopeBind`
<!--
Please fill out this entire template so that we can evaluate your proposal as quickly as possible.
-->

## Proposal

Add an option for `scopeBind` to supress its exception in case, when there is no active scope.

```ts
const maybeBinded = scopeBind(event, { safe: true })
```
In this case, if `scopeBind` called with `safe: true` and there is no scope, then `scopeBind` just returns original event or a function, which calls original event (just like when scope is found)

<!--
  Explain why you need this change and why this cannot be addressed with effector's current set of features.
-->

## Use case

`scopeBind` is meant to be used to bind event or effect to a scope to be called later and the most common use case is to build a bridge of effector events to other reactive source, like websocket, browser api, etc

It works quite well, when used like this:
```ts
const connectSocketFx = attach({
 source: $socket,
 effect(socket) {
   socket.on("message", scopeBind(messageReceived))
 }
})

sample({
 clock: appStarted,
 target: connectSocketFx
})

// later
const scope = fork()

await allSettled(appStarted, {scope})
```
This way it is possible to set scope once, when app is initialized and all related subscribtions will also work in correct scope, which is also useful for tests

But if app doesn't use scopes and only needs Fork API for tests, then `scopeBind` usage is problematic because it throws exception, when scope is not found

And to allow usage both with and without scope users are required to write something like this:
```ts
const safeBind = (event) => {
 try {
   return scopeBind(event)
 } catch(e) {
   return event
 }
}

// later
const connectSocketFx = attach({
 source: $socket,
 effect(socket) {
   socket.on("message", safeBind(messageReceived))
 }
})
```

Built-in option would allow to solve these cases without custom helpers

### Additional contract requirements

When `safe: true` is used without an active scope for an effect, the returned callable must invoke the original effect without throwing because no scope is active. The effect's normal result must be returned to the caller.
