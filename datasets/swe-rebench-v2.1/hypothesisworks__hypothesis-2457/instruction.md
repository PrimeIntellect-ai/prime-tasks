Multiple-error reporting for explicit `@example` phase
Thanks to #2455, I'm writing up a demo test case which has `@example(...)`s which trigger *three* distinct bugs.

Currently, Hypothesis will stop at the first failure.  I'd like to instead report them all, at least when the `report_multiple_bugs` setting is `True`, as we would for generated test cases.  This will involve a bit of poking around in `core.py`, but shouldn't be too bad.

### Additional contract requirements

- `hypothesis.errors.MultipleFailures` is a public exception class.
- When `report_multiple_bugs` is `True` and more than one explicit `@example` fails, the decorated test raises `hypothesis.errors.MultipleFailures`. Its string representation contains a message describing how many explicit examples failed, including that number.
- When `report_multiple_bugs` is `False`, the decorated test raises the first exception encountered from the explicit examples (for example `AssertionError`).


- When exactly two explicit `@example` cases fail, the string representation of the raised exception must contain the literal `2`.
