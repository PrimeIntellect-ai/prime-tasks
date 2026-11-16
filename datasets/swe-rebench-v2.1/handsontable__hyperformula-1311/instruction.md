Operator `+` on ranges throws runtime exception `AbsoluteCellRange: Wrong range size`
### Description

Encountered an internal error while trying some array formula tests. The specific formula `"='Sheet1'!A:A+'Sheet1'!1:1"` I expect to result in a `DetailedCellError` instead.

```ts
import HyperFormula from "hyperformula";

console.log(
  `%c Using HyperFormula ${HyperFormula.version}`,
  "color: blue; font-weight: bold"
);

const hf = HyperFormula.buildFromSheets({
  "Sheet1": [["1"]],
}, {
  licenseKey: "gpl-v3",
  useArrayArithmetic: true,
});

hf.setCellContents({ sheet: 0, row: 0, col: 0 }, "='Sheet1'!A:A+'Sheet1'!1:1")

const sheetName = "Sheet1";
const sheetId = hf.getSheetId(sheetName);
```

### Demo
https://codesandbox.io/s/red-field-hmeldt?file=/src/hyperformulaConfig.js

### Additional contract requirements

- When array arithmetic is enabled and an operation on infinite ranges produces this error, the `DetailedCellError` message must contain `Invalid range size`.
- Add a public static method `CellError.parsingError(detailedMessage?: string)` in `src/Cell.ts` that returns a `CellError` with `ErrorType.ERROR`. When `detailedMessage` is provided, the returned message is the generic parsing-error message `Parsing error.` followed by a single space and the detailed message; when it is omitted, the message is just `Parsing error.`.
