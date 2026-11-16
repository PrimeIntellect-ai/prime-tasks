target() doesn't work with int input
If you call `target()` with an `int` input, you get an error like `hypothesis.errors.InvalidArgument: Expected float but got observation=1 (type=int)`. It's rather unpythonic for a function that takes float inputs to not also work with ints.
