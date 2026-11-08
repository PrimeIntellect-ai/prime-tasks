Serializing bigint sets mutates the underlying entity schema
This was a surprise, the following test fails:
```ts
  it('converts arrays of bigints to sets', async () => {
    const attr = { type: 'set', setType: 'bigint' }
    const result = validateTypes()(attr, 'attr', [
      BigInt(-1234),
      BigInt('123000000000000000000001')
    ])
    expect(result).toEqual(new Set([
      toDynamoBigInt(BigInt(-1234)),
      toDynamoBigInt(BigInt('123000000000000000000001'))
    ]))
    // Should not mutate the attribute
    expect(attr.setType).toEqual('bigint')
  })
```

It seems that when we call `validateType` on a bigint set, we override the `setType` field to `number`, which then causes subsequent reads to lose precision.

[HIDDEN]
```ts
        if (mapping.setType === 'bigint') {
          [HIDDEN]
          value = Array.from(value).map((n) => toDynamoBigInt(n))
        }
```

[HIDDEN]

### Additional contract requirements

- Validating or serializing a bigint set must not mutate the attribute definition: its `setType` must remain `bigint` afterward.
