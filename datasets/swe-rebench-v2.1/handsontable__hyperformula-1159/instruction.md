`Incorrect array size` error for some cases of reversed ranges with absolute addressing (previously: Partially locked, reversed range breaks setCellContents)
### Description

setCellContents on hyperformula instance with the following data causes an "Incorrect array size" error.

```
const tableData = [
  [1, "=SUM(A1:A$1)"],
  [1, "=SUM(A2:A$1)"]
];
```

### Demo
https://codesandbox.io/s/frosty-meadow-umnbk2?file=/src/data.js

Partially locked ranges that are in the correct order work.
Calculating a single reversed and locked formula seems to work fine. See this repo here: https://codesandbox.io/s/silly-leftpad-d38lgu?file=/src/data.js



HyperFormula version: 2.2

### Links
Related #835

### Additional contract requirements

- Add a public static method `AbsoluteCellRange.fromSimpleCellAddresses(start: SimpleCellAddress, end: SimpleCellAddress)` in `src/AbsoluteCellRange.ts`. Each argument is a `SimpleCellAddress` (an object with `sheet`, `row` and `col`). It returns:
  - an `AbsoluteCellRange` when both the row and the column difference between the two addresses are finite,
  - an `AbsoluteRowRange` when only the column difference is infinite,
  - an `AbsoluteColumnRange` when only the row difference is infinite,
  - an `AbsoluteColumnRange` when both the row and the column difference are infinite.
  It throws `SheetsNotEqual` (from `src/errors.ts`) when the two addresses belong to different sheets.
