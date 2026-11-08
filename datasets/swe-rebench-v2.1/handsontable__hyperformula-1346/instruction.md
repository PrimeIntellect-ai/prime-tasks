`Incorrect array size` when calling `MATCH` with a column range referencing an empty sheet (previously: Match Function on Column with Empty Sheet Errors Incorrect Array Size)
### Description

The following code errors with `Incorrect array size`

```ts
Uncaught (in promise) Error: Incorrect array size
    at new ArraySize (ArraySize.js:15:13)
    at new SimpleRangeValue (SimpleRangeValue.js:16:19)
    at SimpleRangeValue.onlyRange (SimpleRangeValue.js:35:12)
    at Interpreter.evaluateAstWithoutPostprocessing (Interpreter.js:222:35)
    at Interpreter.evaluateAst (Interpreter.js:48:20)
    at LookupPlugin.evaluateAst (FunctionPlugin.js:177:29)
    at FunctionPlugin.js:66:43
    at Array.map (<anonymous>)
    at FunctionPlugin.runFunction (FunctionPlugin.js:66:26)
    at LookupPlugin.match (LookupPlugin.js:61:17)
```

```ts
// Create an empty HyperFormula instance.
const hf = HyperFormula.buildEmpty({
  licenseKey: "gpl-v3"
});

// Add a new sheet and get its id.
const table1 = hf.addSheet("table1");
const table2 = hf.addSheet("table2");

// Fill the HyperFormula sheet with data.
hf.setCellContents(
  {
    row: 0,
    col: 0,
    sheet: hf.getSheetId(table1)
  },
  []
);

hf.setCellContents(
  {
    row: 0,
    col: 0,
    sheet: hf.getSheetId(table2)
  },
  [["=MATCH(0, table1!A:A)"]]
);
```

Expected behavior is that `table2!A1` evaluates to `#N/A` since no match occurs. For some reason, `table1!A:A` is parsed as a `CELL_RANGE` instead of a `COL_RANGE`, like in `=SUM(table1!A:A)`.

### Steps to reproduce
https://codesandbox.io/s/spring-cherry-jx071t?file=/src/hyperformulaConfig.js

### Additional contract requirements

- `HyperFormula.buildFromSheets(sheets)` builds an engine from a record of sheet names to two-dimensional arrays.
- `HyperFormula.calculateFormula(formula, sheetId)` evaluates a standalone formula against the given sheet and returns its result.
- A range reference (column, row or cell) to an empty sheet is accepted by `COUNTIF`, `SUM`, `VLOOKUP` and `MATCH` without raising an exception. `MATCH` and `VLOOKUP` evaluate to `#N/A`; `COUNTIF` and `SUM` evaluate to `0`.
