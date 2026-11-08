Raise an error for negative duration in `run()` function
Currently, calling `run(duration)` with a negative duration does not raise an error; instead, it simply runs for 0 seconds.

Proposed Fix:

- Modify `run()` to raise an appropriate error (e.g., ValueError) when a negative duration is passed.
- The case of `run(0*ms)` should remain unchanged, as it is valid and useful in tests.
