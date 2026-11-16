max/min logic is incorrect
Max starts with "SmallestNonzeroFloat64" which is the smallest positive, non-zero value. So max:[0,0], max:[-1,0], max:[-3,-2] and etc. will all get incorrect answer. Also, min is correctly start with maximum value but min:[] return very large number make no sense. It should return null or error *spec in jsonlogic website return null for empty or if it contains not-numeric-castable.
[HIDDEN] Return null for  not-numeric-castable/empty input if want to follow jsonlogic.

### Additional contract requirements

For numeric operands, `max` returns the greatest operand, including zero and negative values. For an empty operand list, either operator returns JSON `null` or reports an error; it must not return a numeric sentinel. These requirements apply to numeric operands; behavior for operands that cannot be converted to numbers is unspecified.
