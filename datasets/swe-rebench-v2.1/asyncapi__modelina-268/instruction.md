Java generator should take additionalItems into consideration
#### Reason/Context
Even though we interpret additionalItems (#224) we do not take it into consideration when rendering the Java types for arrays.

See https://github.com/asyncapi/modelina/issues/224#issuecomment-863200247 for further details on how it should be rendered.

### Additional contract requirements

When rendering the Java type for an array whose `items` is a tuple (a list of schemas), the tuple item types are combined into a single type: if all tuple item types are the same, that type is used; otherwise `Object` is used. When `additionalItems` is present, it is combined with the tuple item types in the same way. The resulting array type is rendered as `<type>[]`, for example `String[]` or `Object[]`.
