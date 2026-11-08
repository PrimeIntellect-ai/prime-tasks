Attribute `names` used by the `primary key` should be unique and shall not be reused by any entities
Attribute `names` used by the `primary key` should be unique and shall not be reused by any entities.

When this happens, TypeDORM should throw a validation error, indicating that this is not allowed.
However, this should still be allowed using explicit `alias` syntax.

i.e this should not be allowed

```typescript
        table: new Table({
            name: tableName,
            partitionKey: 'id',          // <- partition key attribtue name is 'id'
            sortKey: 'sortKey',
        }),
```

```typescript
@Entity({
...
})
class Event {
    @Attribute()
    id!: string;           // <-  'id' name also used as an attribute

    @Attribute()
    sortKey!: number;
}
```

### Additional contract requirements

- The validation error is an instance of a public class `ConflictingAttributeNameError` exported from `@typedorm/common`.
- `ConflictingAttributeNameError` is constructed with a single object argument `{ attributeName: string; entity: string; tableName: string }`.
- A `ConflictingAttributeNameError` instance has `name` equal to `"ConflictingAttributeNameError"` and a `message` that reports the conflicting attribute name and the table name.
