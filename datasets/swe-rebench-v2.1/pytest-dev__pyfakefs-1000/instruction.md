OSError opening same fd twice
**Describe the bug**
Describe the observed behavior, and what you expect to happen instead.
In case of a crash, please provide the complete stack trace.

:wave: in the recent release there were some changes around opening fake files and checking their permissions in #967 which resulted in #983 it looks like.

I have a situation (repro below) where I open the same fd twice and create an io.BufferedRWPair -- with this latest update this fails with the below exception as the file is already opened once.

To be honest im not sure this is a bug or if what I have is not very sane/smart -- the relevant bits for me where vendor'd from pexepct/ptyprocess and ive pretty much left it alone for forever :)

What is/was the reason for only allowing things that aren't pypy to open a file once?

```python
        newline, open_modes = self._handle_file_mode(mode, newline, open_modes)
        opened_as_fd = isinstance(file_, int)
        [HIDDEN]
E                   OSError: [Errno 9] Bad file descriptor

venv/lib/python3.11/site-packages/pyfakefs/fake_open.py:152: OSError
```


**How To Reproduce**
Please provide a unit test or a minimal reproducible example that shows
the problem.

```python
from io import BufferedRWPair
from pyfakefs.fake_filesystem_unittest import Patcher


def test_repro():
    with Patcher(use_cache=False) as patcher:
        fs_ = patcher.fs

        fs_.create_file("dummy")
        dummy_file = open("/dummy")

        fd = dummy_file.fileno()

        readf = open(fd, "rb", buffering=0)
        writef = open(fd, "wb", buffering=0, closefd=False)
        _ = BufferedRWPair(readf, writef)
```

**Your environment**
Please run the following in the environment where the problem happened and
paste the output.

```bash
❯ python -c "import platform; print(platform.platform())"
macOS-14.4.1-arm64-arm-64bit
❯ python -c "import sys; print('Python', sys.version)"
Python 3.11.9 (main, Apr  2 2024, 08:25:04) [Clang 15.0.0 (clang-1500.3.9.4)]
❯ python -c "from pyfakefs import __version__; print('pyfakefs', __version__)"
pyfakefs 5.4.0
❯ python -c "import pytest; print('pytest', pytest.__version__)"
pytest 7.4.4
```


Thanks a bunch for this project, been using it in testing for a long time and its always been so nice and easy to work with!

carl

### Additional contract requirements

- Opening the same fake file descriptor more than once must be permitted; a later open must not fail solely because that descriptor was previously used to open a file.
