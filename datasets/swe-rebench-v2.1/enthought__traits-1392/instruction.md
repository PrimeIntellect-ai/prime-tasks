Dynamic Range traits are not validated when inside a Tuple or List
A dynamic `Range` trait inside a `Tuple` or `List` is not validated correctly.

This issue is analogous to #1385, but for `Range` rather than `Enum`.

Failing test:
```python
    def test_dynamic_range_in_tuple(self):
        # Regression test for #1391
        class HasRangeInTuple(HasTraits):
            low = Int()
            high = Int()
            hours_and_name = Tuple(Range(low="low", high="high"), Str)

        model = HasRangeInTuple(low=0, high=48)
        model.hours = (40, "fred")
        self.assertEqual(model.hours, (40, "fred"))
        with self.assertRaises(TraitError):
            # First argument out or range; should raise.
            model.hours = (50, "george")
```
