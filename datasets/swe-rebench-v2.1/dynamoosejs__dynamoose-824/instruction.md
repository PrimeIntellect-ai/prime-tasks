[BUG] Nested Filters Don't Work
There is an issue when trying to filter nested properties. For example. The following doesn't work.

```js
Model.scan("name.first").eq("Charlie").exec();
```

The reason for this is the request being sent is:

```json
{
  "FilterExpression": "#a0 = :v0",
  "ExpressionAttributeNames": { "#a0": "name.first" },
  "ExpressionAttributeValues": { ":v0": { "S": "Charlie" } },
}
```

The request that should be sent is:

```json
{
  "FilterExpression": "#a0.#a1 = :v0",
  "ExpressionAttributeNames": { "#a0": "name", "#a1": "first" },
  "ExpressionAttributeValues": { ":v0": { "S": "Charlie" } },
}
```

### Additional contract requirements

- `new Condition("name.first").eq("Charlie").requestObject()` must return `{"ConditionExpression":"#a0_0.#a0_1 = :v0","ExpressionAttributeNames":{"#a0_0":"name","#a0_1":"first"},"ExpressionAttributeValues":{":v0":{"S":"Charlie"}}}`.
