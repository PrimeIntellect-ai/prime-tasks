AttributeError: 'FakeFcntlModule' object has no attribute 'LOCK_SH'  (Also 'LOCK_UN' and 'LOCK_EX')
**Describe the bug**
After updating from pyfakefs 5.6.0 to 5.7.0  the following error occurs on `flock` with `fcntl.LOCK_SH`,  `fcntl.LOCK_UN` and `LOCK_EX`.

The error does not occur on version 5.6.0

```
self = <pyfakefs.fake_io.FakeFcntlModule object at 0x7f237a9ba760>, name = 'LOCK_SH'

    [HIDDEN]
E       AttributeError: 'FakeFcntlModule' object has no attribute 'LOCK_SH'
```

**How To Reproduce**
```
import fcntl
from os import path


def lock():
    with open('lock_file', 'a+') as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_SH)
        fcntl.flock(lock_file, fcntl.LOCK_UN)

def test_lock(fs):
    lock()

```

**Your environment**
Please run the following in the environment where the problem happened and
paste the output.
```bash
python -c "import platform; print(platform.platform())"
python -c "import sys; print('Python', sys.version)"
python -c "from pyfakefs import __version__; print('pyfakefs', __version__)"
python -c "import pytest; print('pytest', pytest.__version__)"
```
```
python -c "import platform; print(platform.platform())"
python -c "import sys; print('Python', sys.version)"
python -c "from pyfakefs import __version__; print('pyfakefs', __version__)"
python -c "import pytest; print('pytest', pytest.__version__)"
Linux-6.10.11-200.fc40.x86_64-x86_64-with-glibc2.39
Python 3.9.16 (main, Sep  6 2024, 09:21:47)
[GCC 14.2.1 20240801 (Red Hat 14.2.1-1)]
pyfakefs 5.7.0
pytest 8.3.3

```

### Additional contract requirements

- When `fcntl` is available, `fcntl.LOCK_SH`, `fcntl.LOCK_UN`, and `fcntl.LOCK_EX` must be accessible while using pyfakefs.
- A shared-lock call followed by an unlock call using `fcntl.flock` on a file opened in the fake filesystem must succeed.
