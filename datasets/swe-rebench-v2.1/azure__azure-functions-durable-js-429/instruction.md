Simplify the `client.startNew()` experience
Based on discussion [here](https://github.com/ejizba/func-nodejs-prototype/pull/14#discussion_r1044721159). Currently, the default HTTP starter `client.startNew()` call looks like this:

```TS
const instanceId = await client.startNew(request.params.orchestratorName, undefined, request.text());
```

Ideally, `client.startNew()` should accept one single object as an argument, rather than 3 distinct arguments, so that:

1. It's clearer what each argument is for
2. Order doesn't matter
3. Unnecessary arguments can be omitted instead of passing in `undefined`.

Since this would be a breaking change, it might be better to include this change with the rest of the v3.x new programming model changes.

### Additional contract requirements

`startNew` continues to take the orchestrator function name as its required first argument. The previously separate optional instance ID and orchestrator input are supplied through one optional second-argument object, using the `instanceId` and `input` fields. Either field may be omitted when it is not needed.
