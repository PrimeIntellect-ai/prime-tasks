Allow updating items with empty values for attributes
When trying to build update expression for attribute with falsy value, expression fails with "no value for given expression name"

### Additional contract requirements

- `ExpressionBuilder.buildUpdateExpression(item)` must accept attribute values that are `undefined` or `null` and must include them in the generated `ExpressionAttributeValues` with the value `null`, instead of failing with "no value for given expression name".
- Empty string attribute values must be preserved as-is in `ExpressionAttributeValues`.
- Non-nullish falsy attribute values, including `false` and `0`, must be accepted and preserved as-is in `ExpressionAttributeValues`.


- For an item with the key `user.name`, `buildUpdateExpression` must use `UpdateExpression: 'SET #attr0_inner0.#attr0_inner1 = :val0'` and `ExpressionAttributeNames: { '#attr0_inner0': 'user', '#attr0_inner1': 'name' }`.
