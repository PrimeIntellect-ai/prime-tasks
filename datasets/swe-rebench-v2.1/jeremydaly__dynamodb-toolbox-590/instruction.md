Numbers do not deserialize correctly on 0.8+ with wrapNumbers: true
When fetching values stored as `number` types in Dynamo (either `number`, or `bigint` when written with older versions of the SDK), the values come back as `{value: "12345"}`.

However, this line of code in `formatItem.ts` assumes they come back as flat strings:
```
  if (attr && attr.type === 'number') {
    value = Number(value as number)
  }
```
I assume that this is probably true if `wrapNumbers` is set to `false`, but when using `wrapNumbers` some additional logic is needed to correctly transform these values.

I've patched this locally with the following, which is horrendous but does seem to fix the issue:
[HIDDEN]

The following test reproduces this issue, provided you have a compatible dynamo instance running locally:

```ts
const TestTable = new Table({
  name: 'test-table',
  partitionKey: 'pk',
  sortKey: 'sk',
  DocumentClient: DocumentClientWithWrappedNumbers
})

const TestEntity = new Entity({
  name: 'TestEntity',
  autoExecute: false,
  attributes: {
    email: { type: 'string', partitionKey: true },
    sort: { type: 'string', sortKey: true },
    test: 'string',
    num: 'number',
  },
  table: TestTable
} as const)

it('round-trips a number', async () => {
  const sk = randomUUID();
  await TestEntity.put({
    pk: 'test-pk',
    sk,
    num: 1337,
  }, { execute: true });
  const {Item: value} = await TestEntity.get({
    pk: 'test-pk',
    sk,
  }, { execute: true });
  console.log(value);
  expect(value.num).toEqual(1337); // fails
})
```
The entity that comes back is:
```ts
    {
      sort: '37a4cfaa-0dcc-455f-aa25-2fed8ca781ad',
      created: '2023-09-18T20:20:11.763Z',
      email: 'test-pk',
      modified: '2023-09-18T20:20:11.763Z',
      entity: 'TestEntity',
      num: NaN
    }
```

### Additional contract requirements

A bigint-typed attribute received as a wrapped DynamoDB number must deserialize to its JavaScript bigint value.
