Add support for class-transformer versioning
We recently began introducing some changes to our data model/schema, and it would make life a whole lot simpler if we could leverage `class-transformer`'s built-in support for [versioning attributes](https://github.com/typestack/class-transformer#using-versioning-to-control-exposed-and-excluded-properties) (using `since` and `until`) when using TypeDorm.  The idea would be to designate an attribute as the schema version identifier, and then pass along that version number to `class-transformer` when doing serialization/deserialization.  That would enable us to gracefully deprecate older schema versions and seamlessly "upgrade" to newer schema versions over time.  An example of what this might look like:


```ts
@Entity({
  table: testTable,
  name: 'item',
  primaryKey: {
    partitionKey: 'ITEM#{{id}}',
  },
  schemaVersionAttribute: 'schemaVersion'
})
export class TestEntity {
  @Attribute()
  id: string;

  @Expose({ since: 2, until: 3 })
  @Attribute()
  attributeInVersion2And3: string;

  @Expose({ since: 3 })
  @Attribute()
  attributeSinceVersion3: string;

  @Attribute()
  schemaVersion: number;
}
```
