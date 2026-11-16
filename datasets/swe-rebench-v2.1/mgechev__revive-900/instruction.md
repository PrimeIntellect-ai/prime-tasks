Linter rule to enforce empty slice declaration/initialization style
**Is your feature request related to a problem? Please describe.**
Styles:

1. slice := make([]type)
2. slice := []type{}

There is also a way of having a non-initialized slice (which should be preferred over the empty slice w/o len and cap in most cases), but this is beyond the scope of this linter

**Describe the solution you'd like**
I'd like to introduce a new linter that will enforce a particular style of these 3 to be used.

Things to take into account:

- slices with elements (i.e. `[]type{el1, el2, elN}`) - they should be ignored by the linter.
- slices with explicit len and (optionally) capacity: i.e. `make([]type, len)`, `make([]type, len, cap)` - they should be ignored by the linter.

**Describe alternatives you've considered**
I wasn't able to find any working alternative.

**Additional context**
This can be considered as a follow up feature for #892.

### Additional contract requirements

- Add a linter rule named `enforce-slice-style`, exposed in package `rule` as the type `EnforceSliceStyleRule`, implementing the `lint.Rule` interface.
- The rule accepts an optional configuration argument: a string that is one of `"make"`, `"literal"`, or `"any"`. When no argument is supplied the style is `"any"`. The `"any"` style performs no enforcement.
- When the style is `"make"`, an empty slice literal is reported with the failure message `use make([]type) instead of []type{} (or declare nil slice)`.
- When the style is `"literal"`, a `make` call with zero length is reported with the failure message `use []type{} instead of make([]type, 0) (or declare nil slice)`, unless it specifies a positive capacity. Calls with an omitted capacity or a zero capacity are reported; calls with a positive capacity are not.
