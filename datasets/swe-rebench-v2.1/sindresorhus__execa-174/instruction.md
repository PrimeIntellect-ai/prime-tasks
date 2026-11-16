Make the child process closer to a real Promise
Execa doesn't implement `.finally()` on the child process. This is making it difficult to come up with a correct Flow type definition for it – see discussion [on this PR](https://github.com/flow-typed/flow-typed/pull/2585).

Would you object to adding a `.finally()` method to execa's spawned child process, to make it fully implement `Promise`?

The `.finally()` method is at Stage 4 and is in the latest [draft spec](https://tc39.github.io/ecma262/#sec-promise.prototype.finally).

### Additional contract requirements

The child process's `.finally()` method invokes its callback after either fulfillment or rejection, without passing settlement arguments. If the callback completes normally, the returned promise preserves the child's original fulfillment value or rejection reason. If the callback returns a promise, the returned promise waits for it to settle; if it fulfills, the original settlement is preserved, and if it rejects, the returned promise rejects with that rejection reason. If the callback throws, the returned promise rejects with that error.
