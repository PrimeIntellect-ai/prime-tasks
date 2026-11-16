Mass edit of new blank cells corrupts project in 3.9.2
Initially mentioned in [this forum thread](https://forum.openrefine.org/t/after-adding-rows-and-editing-a-cell-project-failing-to-load/2214)

### To Reproduce
Steps to reproduce the behavior:
1. Using OpenRefine 3.9.2
2. Open any project
3. Add multiple rows to the end of the project
4. Edit one of the cells and click "Apply to all identical cells"



### Current Results
The project cannot be loaded. After editing and upon re-opening the project, the browser is redirected to the loading screen.
### Expected Behavior
The result entered into the edit dialog box should be applied to all empty cells in the column.

### Versions
 - Operating System: Ubuntu 24.04
 - Browser Version: Firefox 136.0.3
 - JRE or JDK Version: 21.0.5
 - OpenRefine: 3.9.2

### Additional contract requirements

- `com.google.refine.model.Cell` must provide a public method `deepCopy()` returning a new `Cell` that has the same value and an independent copy of its `Recon`, or a `null` `Recon` when the original `Recon` is `null`.
- `com.google.refine.model.Row` must provide a public method `deepCopy()` returning a new `Row` with the same flagged and starred state and independent copies of its cells.
- `com.google.refine.operations.row.RowAdditionOperation` must provide a public constructor `RowAdditionOperation(List<Row> rows, int insertionIndex)`.
- A `RowAdditionOperation` must be deserializable from JSON that stores the rows under the `addedRows` property, and must serialize its rows back under the `addedRows` property.
- A `RowAdditionOperation` must also be deserializable from the legacy JSON format that stores the rows under the `rows` property; in that case the number of rows is preserved and their contents are ignored, so that the rows are treated as empty.
- Applying a `com.google.refine.model.changes.RowAdditionChange` to a `Project` must insert independent copies of the rows at the insertion index, so that later edits to the project's rows do not modify the rows held by the operation.
