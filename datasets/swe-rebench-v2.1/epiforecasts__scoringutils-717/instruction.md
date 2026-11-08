Let `pairwise_comparison()` error upon failure
`pairwise_comparison()` currently returns `NULL` and throws a warning if something goes wrong. Likely it should just error. Similarly, `add_pairwise_comparison()` has to [HIDDEN].

### Additional contract requirements

- When `pairwise_comparison()` cannot complete a comparison, it must raise an error rather than issue a warning and return `NULL`.
- When `add_pairwise_comparison()` cannot perform a comparison, it must also fail with an error rather than return `NULL`.
