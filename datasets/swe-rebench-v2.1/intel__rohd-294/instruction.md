An equality operator for `LogicValues` that supports "don't care"
## Motivation
There are cases where you want to compare two `LogicValues` values for some bits, but not all bits.  It would be nice to support an equality check that enables a comparison of two `LogicValues` where any `x` is treated as a "don't care if this bit is equal".  Some thought would need to be put into whether only one side of the comparison should consider `x` as don't care or both sides, or maybe that should be configurable.  This feature is similar to a `casez` but for values instead of hardware.

## Desired solution
Add a function for comparison with don't care to `LogicValues`.

## Alternatives considered
Let users implement this functionality themselves as needed.

### Additional contract requirements

Provide a public instance comparison function named `LogicValue.equalsWithDontCare(LogicValue other)`. At each bit position, an x in either value makes that position a don't-care.
