isort does not skip files
**Describe the bug**

`isort` does not respect `skip` and `skip_glob` configuration options.

**To Reproduce**

Steps to reproduce the behavior:

1. Create `file.py` with the following content:
    ```python
    import os, \
        sys
    ```
2. Create `.isort.cfg` with the following content:
    ```
    [settings]
    skip_glob = file.py
    ```
3. Run `isort file.py`.
4. Open `file.py` and check out it's content to become:
    ```python
    import os
    import sys
    ```

**Expected behavior**

A `file.py` is skipped and is not touched.

**Screenshots**

—

**Environment (please complete the following information):**

- OS: Linux
- Python version: 3.7.2
- isort version: 4.3.11

**Additional context**

`isort` 4.3.10 is working correctly. Issue can be reproduced with `skip` option as well.
