`NULL` converted to `0` when fetching data
My table is configured to NOT remove null attributes
```
removeNullAttributes: false,
```

I have two attributes defined as
```
attr1: { type: 'number' },
attr2: { type: 'string' },
```

Saved them both as `null`, checking on Dynamo as expected, we have:

```
"attr1": {
    "NULL": true
  },
"attr2": {
    "NULL": true
  },
```

However, when getting the item back from Dynamo, I get

```
attr1: 0,
attr2: null,
```

I don´t see why any conversion took place for the number
But even if a conversion (null to 0) were to take place, it should have also taken place when saving the data to dynamoDB and saved 0, not NULL.
