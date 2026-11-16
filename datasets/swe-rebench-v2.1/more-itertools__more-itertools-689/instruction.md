[Feature Request] inverse_nth_*
### Description

The inverse of `nth_combination`, `nth_permutation`, etc ... functions.

For example, it would have a signature `inverse_nth_combination(iterable, r, comb)`
and would return `list(combinations(iterable, r)).index(sorted(comb))`
without enumerating all combinations.

### Additional contract requirements

The requested function is `combination_with_replacement_index(element, iterable)`, the inverse of enumerating `itertools.combinations_with_replacement`. It returns the zero-based lexicographic index of a valid combination-with-replacement of `iterable` without enumerating the preceding combinations, and raises `ValueError` when `element` is not a valid combination-with-replacement.

A `None` value is treated like any other value in `iterable`: combinations containing it are indexed normally, and an element containing `None` that is absent from `iterable` is invalid.
