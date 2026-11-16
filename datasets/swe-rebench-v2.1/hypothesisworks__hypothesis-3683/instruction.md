tests/cover/test_lookup.py::test_resolving_mutually_recursive_types{,_with_defaults} fail randomly when running the test suite w/ xdist
Well, you're not going to like this but I'm getting quasi-random test failures from the following two tests when running the large subset of the test suite in parallel:

```
FAILED tests/cover/test_lookup.py::test_resolving_mutually_recursive_types - RecursionError: maximum recursion depth exceeded
FAILED tests/cover/test_lookup.py::test_resolving_mutually_recursive_types_with_defaults - RecursionError: maximum recursion depth exceeded
```

This seems to be very flaky. It has been happening to us with PyPy3 before but I've assumed it's PyPy-specific. With 6.76.0, it suddenly started happening with CPython 3.11 as well. Curiously enough, I can reproduce it reliably when running a very specific set of tests:

```
python -m pytest -n 12 tests/cover tests/pytest tests/quality
```

but if I change tested files even a little, it stops happening.

Full log with tracebacks: [dev-python:hypothesis-6.76.0:20230606-074652.log](https://github.com/HypothesisWorks/hypothesis/files/11662376/dev-python.hypothesis-6.76.0.20230606-074652.log)

I realize this is going to be very hard to reproduce, and I'll be glad to try anything you may suggest while I still can.

### Additional contract requirements

- In the limited-stack case, after setting `sys.setrecursionlimit(current_stack_depth + 100)`, invoking the `@given` test must leave `sys.getrecursionlimit()` equal to `current_stack_depth + 100`.
