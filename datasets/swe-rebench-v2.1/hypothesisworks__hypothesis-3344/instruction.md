Teach `from_type()` to handle `TypedDict` classes with PEP-655 `(Not)Required` keys
[PEP-655](https://peps.python.org/pep-0655/) defines a better way to mark some keys as required and others as not-required on the `TypedDict` class - before, you had to define a parent class with some keys and a child class with others.  We should upgrade our resolver code to handle this, and write test cases for both pure-new-style and mixes of inheritance-based (old) and `(Not)Required`-based (new) styles.

https://github.com/HypothesisWorks/hypothesis/blob/2a071c88df9f4661e71623ca6a58de8ec5098b6c/hypothesis-python/src/hypothesis/strategies/_internal/core.py#L1075-L1095

Prior work on recent types: #3331, #3280, #2978.
