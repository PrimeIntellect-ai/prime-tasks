Add sample, randrange, and getrandbits to B311 random module check?
**Is your feature request related to a problem? Please describe.**
I noticed that `random.choice` raises a B311 warning [here](https://github.com/PyCQA/bandit/blob/e4da0b351f89a82b5de8dd791cbdd963476b5a11/bandit/blacklists/calls.py#L513). I assume this is to try to stop someone from using it with a `range()` in security-related code. I noticed some other `random` functions that could be used in a similar way but are not currently checked: [`sample`](https://docs.python.org/3/library/random.html#random.sample), [`randrange` and `getrandbits`](https://docs.python.org/3/library/random.html#functions-for-integers).

**Describe the solution you'd like**
Add `random.sample`, `random.randrange`, and `random.getrandbits` to B311 check

**Describe alternatives you've considered**
None

**Additional context**
N/A

Love this idea? Give it a 👍. We prioritize fulfilling features with the most 👍.

### Additional contract requirements

- Also add calls to `random.sample`, `random.randrange`, and `random.getrandbits` in `examples/random_module.py` so the functional check exercises these additions.
