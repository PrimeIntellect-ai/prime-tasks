Improve `optimal-quantifier-concatenation`
There is a whole class of fixable problems `optimal-quantifier-concatenation` (OQC) can't detect yet. Right now, OQC can only detect (and fix) the concatenation of single-character quantifier (e.g. `\d*\w*`). It's can't detect anything else.

OQC should also be able to detect (and fix) `(?:foo)?\w+` == `\w+`.

More generally, if we have a single-character quantifier `A{n,∞}` and a quantifier `B{p,q}`, we will be able to simplify `B{p,q}` to `B{p}` if all possible consumed characters of `B` are a subset of `A` (`getConsumedCharacters(B) ⊆ getConsumedCharacters(A)`).

### Additional contract requirements

- For `/\w+(?:foo|bar)?/`, report exactly: "'(?:foo|bar)?' can be removed because it is already included by '\w+'."
- For `/[ab]*(?:a|bb)+/`, report exactly: "'[ab]*' and '(?:a|bb)+' can be replaced with '[ab]*(?:a|bb)'."
- A quantifier `N` nested inside a group or alternative can also be simplified to `F` (or removed) because of an adjacent single-character quantifier `D` when all possible consumed characters of `N` are a subset of `D`. Report exactly "'N' can be replaced with 'F' because of 'D'." when `N` is simplified, and exactly "'N' can be removed because of 'D'." when `N` is removed.
