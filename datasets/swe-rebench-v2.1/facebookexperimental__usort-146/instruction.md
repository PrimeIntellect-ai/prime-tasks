Unstable sorting with mixed category imports
When basic imports include modules from multiple categories, sorting can be unstable [HIDDEN]:

Test case:

```py
    def test_sorting_mixed_category_imports(self) -> None:
        self.assertUsortResult(
            """
                import os, attr
                import difflib
                import third_party
            """,
            """
                import difflib

                import attr, os
                import third_party
            """,
        )

```

Produces the following test failure:

```
(.venv) jreese@butterfree ~/workspace/usort mixed± » make format test lint
python -m ufmt format usort setup.py
python -m coverage run -m usort.tests
.......................................................................F.............
======================================================================
FAIL: test_sorting_mixed_category_imports (usort.tests.functional.UsortStringFunctionalTest)
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/Users/jreese/workspace/usort/usort/tests/functional.py", line 632, in test_sorting_mixed_category_imports
    self.assertUsortResult(
  File "/Users/jreese/workspace/usort/usort/tests/functional.py", line 58, in assertUsortResult
    self.fail(
AssertionError: µsort result was not stable on second pass:

Before:
-------

import os, attr
import difflib
import third_party

First Pass:
-----------

import attr, os
import difflib

import third_party

Second Pass:
------------

import difflib

import attr, os

import third_party


----------------------------------------------------------------------
Ran 85 tests in 4.119s

FAILED (failures=1)
make: *** [test] Error 1
```

### Additional contract requirements

- Basic imports spanning multiple categories must be sorted into canonical category order, as demonstrated by the example. Sorting the resulting normalized import block again must leave it unchanged.
