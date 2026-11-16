Using $set operator can leave unused ExpressionAttributeNames in query
When performing an update operation with the `$set` operator, it is possible to end up with an invalid DynamoDB request. Using the following example works fine where `item.partialMap` is not an empty object, and the resulting DynamoDB request correctly includes all relevant components for `UpdateExpression`, `ExpressionAttributeNames` and `ExpressionAttributeValues`.
```js
await Variants.update({
        pk: item.pk,
        sk: item.pk,
        someMap: { $set: item.partialMap }
});
```

However, if `item.partialMap` has no keys, the resulting DynamoDB request has the correct `UpdateExpression` and `ExpressionAttributeValues` (neither reference the non-existent properties) but `ExpressionAttributeNames` continues to reference `#someMap`, causing the update operation to fail with the following error:

> Value provided in ExpressionAttributeNames unused in expression: keys: {#someMap}'

We can work around this by using [custom clauses](https://github.com/jeremydaly/dynamodb-toolbox#adding-custom-parameters-and-clauses) but it feels like the library should be filtering any unused attribute names out of the auto-generated query.
