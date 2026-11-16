Make signatures of `simpleCellAddressToString` and `simpleCellRangeToString` more logical
### Description
<!--- [mandatory] Describe the functionality that should be added to the engine-->

Currently `sheetId` needs to be passed twice to `simpleCellAddressToString`:

```js
const cellAddress = { sheet: sheetId, row: 0, col: 3};
const cellAddressAsString = hfInstance.simpleCellAddressToString(cellAddress, sheetId);
```

~~The second argument to `simpleCellAddressToString` should be optional. Do not remove it completely to keep backwards compatibility.~~ See comments


### Links
<!--- [optional] Any links that are related  -->

### Additional contract requirements

Both `simpleCellAddressToString` and `simpleCellRangeToString` can be called without a second argument. In that case, each method uses the sheet ID in the supplied address or range to resolve the sheet, rather than requiring the caller to repeat it. The existing A1-style string output omits the sheet name by default.
