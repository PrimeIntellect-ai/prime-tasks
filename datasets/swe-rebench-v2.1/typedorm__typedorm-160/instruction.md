Entity index attributes not returned in findOne/ find  api responses
### Discussed in https://github.com/typedorm/typedorm/discussions/156

<div type='discussions-op-text'>

<sup>Originally posted by **Sachin-Radhakrishnan** July 29, 2021</sup>

Hi,

I tried to get an item from dynamodb using findOne() api , but the response returned is missing the the index attribute (email) and its value . Is it the expected behaviour? Is there any way to get it ?

This is the structure of my entity
```typescript
@Entity({
    name: 'sample-entity',
    primaryKey: {
        partitionKey: 'en#' + uuidv4(),
        sortKey: 'root',
    },
    indexes: {
        [process.env.EMAIL_INDEX!]: {
            type: INDEX_TYPE.GSI,
            partitionKey: '{{email}}',
            sortKey: ''
        }
    }
})
export default class EntityData  {

    @Attribute()
    name!: string;

    @Attribute()
    email!: string;

}
```
</div>
