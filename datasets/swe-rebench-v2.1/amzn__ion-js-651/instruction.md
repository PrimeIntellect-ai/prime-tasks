LST discards duplicate symbols in import, invalidating SIDs
When `ion-js` reads binary Ion data that includes a local symbol table, it checks to see whether each string being added to the table is already present. If it is, [it skips that string](https://github.com/amzn/ion-js/blob/217feef0ca0cd462f6909ead17f386579fdded0a/src/IonLocalSymbolTable.ts#L62-L63). The symbol is not added and the number of entries in the symbol table no longer aligns with the table that was used to encode the data. This behavior is incorrect and causes Errors to be thrown when reading Ion written by libraries other than `ion-js`.

For example, this Ion text:

```js
{
  files: [
    {name: "img1", format: "JPG", bytes: 552},
    {name: "img2", format: "PNG", bytes: 716},
    {name: "img3", format: "GIF", bytes: 1091},
    {name: "notes", format: "TXT", bytes: 480},
  ]
}
```

contains the symbols `files`, `name`, `format`, and `bytes`.

A writer encoding that data into binary might (unwisely) choose to add `name` to the symbol table again even though [it's already in the system symbol table as SID `$4`](http://amzn.github.io/ion-docs/docs/symbols.html#system-symbols), creating a new SID `$11`.

Ignoring the duplicate symbol means that every starting at SID `$11` will map to incorrect text or to no text at all, leading to corrupted data and exceptions like the following:

```
Error: Symbol $20 greater than maxID.
    at BinaryReader.getSymbolString (src/IonBinaryReader.ts:249:23)
    at BinaryReader.fieldName (src/IonBinaryReader.ts:128:21)
    at _loadStruct (src/dom/index.ts:118:29)
    at _loadValue (src/dom/index.ts:108:38)
    at Object.load (src/dom/index.ts:68:44)
```
LocalSymbolTable treats Object properties as symbols
Follow-on to #645, which centered on `SharedSymbolTable`.

`LocalSymbolTable` [stores its symbols in an `Object`](https://github.com/amzn/ion-js/blob/b3abd8a58a2fc8eb1b2538cdfe767303dbfcc585/src/IonLocalSymbolTable.ts#L27) (not a `Map`). Unfortunately, [HIDDEN]
```typescript
[HIDDEN]
```
This creates an `Object` with the `Object` prototype, which includes a variety of properties including `toString`, `toLocaleString`, `valueOf`, etc. When `LocalSymbolTable` to checks to see whether a given string is in the table, it returns false positive for these `Object` properties.

[HIDDEN]

### Additional contract requirements

- A string that exists only as an inherited property of JavaScript’s Object prototype must not be treated as a symbol already present in a local symbol table.
