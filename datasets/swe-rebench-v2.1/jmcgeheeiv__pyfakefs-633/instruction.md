Behavior difference for os.path.split
**Describe the bug**
On windows, the function python version of `os.path.split` does not convert path separators, while the pyfakefs version does. Is this intentional or is this a bug?

**How To Reproduce**

```python
import os
import unittest
from pyfakefs.fake_filesystem_unittest import TestCase


class TestPathSplit(TestCase):

    def test_split(self):
        head_before, tail_before = os.path.split('/')
        self.setUpPyfakefs()
        head_after, tail_after = os.path.split('/')
        print("Before setUpPyfakefs head=%s, tail=%s" % (head_before, tail_before))
        print("After  setUpPyfakefs head=%s, tail=%s" % (head_after, tail_after))
        self.assertEqual(head_before, head_after)

if __name__ == '__main__':
    unittest.main()
```

```bash
>test.py
Before setUpPyfakefs head=/, tail=
After  setUpPyfakefs head=\, tail=
F
======================================================================
FAIL: test_split (__main__.TestPathSplit)
----------------------------------------------------------------------
Traceback (most recent call last):
  File "C:\Users\Russ\Desktop\backup-tool\bug-report\test.py", line 14, in test_split
    self.assertEqual(head_before, head_after)
AssertionError: '/' != '\\'
- /
+ \
```

**Your environment**

```bash
>python -c "import platform; print(platform.platform())"
Windows-10-10.0.19041-SP0

>python -c "import sys; print('Python', sys.version)"
Python 3.9.1 (tags/v3.9.1:1e5d33e, Dec  7 2020, 17:08:21) [MSC v.1927 64 bit (AMD64)]

>python -c "from pyfakefs.fake_filesystem import __version__; print('pyfakefs', __version__)"
pyfakefs 4.5.0
```

### Additional contract requirements

- `FakeFilesystem.splitpath` must preserve repeated leading root separators rather than collapsing them.
- When a fake filesystem has both a primary and an alternative path separator, `splitpath` must recognize either separator when separating the final component, including in drive-prefixed and UNC paths and when a path ends in a separator. It must preserve the original separator spelling in the returned path portions.
- In Windows mode, `splitdrive` must distinguish drive-letter and UNC share prefixes from ordinary paths when either configured separator is present, while preserving the remaining path text.
- `splitpath` and `splitdrive` must preserve whether the input is a string or a byte string.
