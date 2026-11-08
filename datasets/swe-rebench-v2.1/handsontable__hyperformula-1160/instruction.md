Removing Sheet Errors With Vertex for address missing in AddressMapping
### Description

Running into a bug where when removing a sheet, it runs into a self-circular dependency bug trying to delete cell values that reference itself. [HIDDEN]

### Demo
https://codesandbox.io/s/small-thunder-4j9w0m?file=/src/hyperformulaConfig.js

### Additional contract requirements

- Removing a sheet that contains a formula referring to a cell on that same sheet must complete without a self-circular-dependency error; callers must not need to clear the sheet first.
- Removing a sheet must leave data in other existing sheets intact, including sheets referenced by formulas on the removed sheet.
