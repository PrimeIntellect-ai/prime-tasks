Allow reference to other fields when inserting or updating a document
```js
genji> insert into foo values {
  base: 379.99,
  vat: 20,
  total: base + base * vat / 100
};
```

### Additional contract requirements

- When the first document is inserted into an empty table without an explicit primary key, its serialized document includes `"pk()":1`.
