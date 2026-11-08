walrus doesn't work in and/or
(Found by @GBeauregard on Discord)

Example test case:
```python

    @skip_before((3, 8))
    def test_and(self):
        self.assert_passes(
            """
            from typing import Optional

            def opt() -> Optional[int]:
                return None

            def capybara(cond):
                if (x := opt()) and cond:
                    assert_is_value(x, TypedValue(int))
                assert_is_value(x, TypedValue(int) | KnownValue(None))
            """
        )
        self.assert_passes(
            """
            def func(myvar: str, strset: set[str]):
                if (encoder_type := myvar) and myvar in strset:
                    print(encoder_type)
            """
        )
```

[HIDDEN] But this needs to change so that name bindings from the walrus survive.

This probably also affects ternary: `(x := 2) if some_condition else (x := 1)`. That's much less likely to appear in real code though.

### Additional contract requirements

- Walrus-assigned names in `and` and `or` expressions must remain available after the expression, without losing the logical expression's normal narrowing behavior.
- Ternary expressions are also in scope: when both branches assign to the same name with a walrus operator, that name must remain available afterward with a value that accounts for the alternatives from both branches.
