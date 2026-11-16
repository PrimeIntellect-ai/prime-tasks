Feature: get a list of named expressions used by a formula
Create a method that returns a list of named expressions in a formula.

The method should take a cell address as parameter or the formula as string, whichever is better, easier or more consistent with the rest of the API.

Originally requested in https://github.com/handsontable/hyperformula/discussions/1077#discussioncomment-3879351

### Additional contract requirements

- Add a public method `getNamedExpressionsFromFormula(formulaString: string): string[]` on the `HyperFormula` class.
- The method returns the names of the named expressions referenced by the given formula, in order of first appearance. Each name appears at most once. If the formula references no named expressions, it returns an empty array.
- The method must not evaluate the formula.
- If `formulaString` is not a string, the method throws `ExpectedValueOfTypeError`.
- If `formulaString` is empty, does not start with `=`, or cannot be parsed as a formula, the method throws `NotAFormulaError`.
