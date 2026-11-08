Strategy type annotations - explicit Optional
A lot of the strategies in [core](https://github.com/HypothesisWorks/hypothesis/blob/master/hypothesis-python/src/hypothesis/strategies/_internal/core.py) take parameters that can be `None`-valued but aren't typed as `Optional`. For example,

``` python
def integers(min_value: int = None, max_value: int = None) -> SearchStrategy[int]:
```

which can cause issues if mypy is run with `--no-implicit-optional`. The only strategy that has (partially) typed `Optional` in core is `complex_numbers`:

``` python
def complex_numbers(
    *,
    min_magnitude: Optional[Real] = 0,
    max_magnitude: Optional[Real] = None,
    allow_infinity: bool = None,
    allow_nan: bool = None
) -> SearchStrategy[complex]:
```

Would you like to have a PR updating the rest of the strategies with explicit `Optional` types or do you prefer relying on implicit optional (in which case perhaps remove it from `complex_numbers` for consistency)?

### Additional contract requirements

- The `None`-accepting parameters of `complex_numbers` must follow one consistent annotation policy: either annotate all of them explicitly as optional, or rely on implicit optionals for all of them.
- `complex_numbers` must continue to accept `None` for `min_magnitude`, treating it as zero.
