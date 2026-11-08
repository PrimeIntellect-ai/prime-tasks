[Feature Request] support for operationId
It can be very useful to support it :
https://swagger.io/docs/specification/paths-and-operations/

### Additional contract requirements

- When a path JSDoc comment contains an `@operationId <value>` tag, the generated operation object for that path and HTTP method includes an `operationId` property whose value is the tag's description (for example, `@operationId getInfo` produces `operationId: 'getInfo'`).
- When no `@operationId` tag is present, the generated operation object does not include an `operationId` property.
