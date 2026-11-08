Signal copy
Simple method to return copy of a signal object, similar to numpy.copy().

### Additional contract requirements

- Provide a `Signal.copy()` method that returns a distinct `Signal`.
- The copy preserves the source signal's observable state.
- Its mutable signal data is independent: changing data in the copy does not change the original.
