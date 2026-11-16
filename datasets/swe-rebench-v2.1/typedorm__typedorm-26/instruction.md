Store entity name as an attribute on dynamo item
Store entity name on item

May be also add an prefix, something like
`__en`: short for entity name

### Additional contract requirements

- Persist the entity name under the exact attribute key `__en`; for the `User` entity, its value must be `'user'`.
