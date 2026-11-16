Orchestrator values are not passed if not objects
If I have a simple string the orchestrator return no input values
```js
client.startNew(orchestrator, undefined, "bla")
```
```js
const input = context.df.getInput();
// input will be null;
```


I imagine this can be related with the change to use Axios now.
And in order to make my code work I needed to change the code in start new from
```js
const response = await axios.post(requestUrl, JSON.stringify(input));
```
to
```js
[HIDDEN]
```

### Additional contract requirements

- When starting a new orchestration instance, the client must send the orchestrator input to the Durable Functions extension as JSON, with the request's `Content-Type` header set to `application/json`. This applies to string inputs as well as object inputs, so that the extension can deserialize the input and make it available to the orchestrator.
