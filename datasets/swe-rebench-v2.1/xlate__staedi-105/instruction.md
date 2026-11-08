EDIFACT Syntax Rule D7 (If first, then none of the others)
### If first, then none of the others: `D7(030,040,050)`
If the first item (at position 03) is present, then the items at 04 and 05 cannot be included.

### Additional contract requirements

- When this rule is violated, the reported error location must identify element position 3.
- The rule is selected in a schema by the syntax type value `firstonly`, i.e. `<syntax type="firstonly">`.
- A violation is reported as the `EDIStreamValidationError.EXCLUSION_CONDITION_VIOLATED` error.
