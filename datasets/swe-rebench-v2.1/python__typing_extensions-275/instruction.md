Behavior of types.get_original_bases() changed in Python 3.12
There was just a pull request merged into Python 3.12 to change how `types.get_original_bases()` behaves for generic types whose bases have no type arguments.

* **Issue**: python/cpython#107576
* **Pull Request**: python/cpython#107584

The TL;DR is that `types.get_original_bases(cls)` should only use `cls`'s *own* `__orig_bases__`, not an ancestor type's via MRO, and should fall back to `cls.__bases__` otherwise.
