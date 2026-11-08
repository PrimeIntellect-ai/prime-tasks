The `io.open` function should not consider file permissions when opening from an existing file descriptor
**Describe the bug**
The low-level `os.open` function supports creating writable file handles to newly created read-only files. The returned file descriptor is valid for writing to the file, and `io.open` allows creating a writer for that file handle. When `pyfakefs` handles `io.open`, it checks the permissions on the underlying file object, which the built-in `open` does not.

**How To Reproduce**
The following test cases will demonstrate the issue:

```python
def _do_test_good_fdopen(base: Path):
    # Create a writable file handle to a read-only file
    f = base / "file.txt"
    fd = os.open(f, os.O_CREAT | os.O_WRONLY, 0b101_101_101)
    with open(fd, "w") as out:
        out.write("hey")
    assert f.read_text() == "hey"
    f.unlink()

def test_realfs_good(tmp_path: Path):
    _do_test_good_fdopen(tmp_path)

def test_fakefs_good(fs):
    _do_test_good_fdopen(Path("/"))
```


# Bonus: `open` Mode Mismatching

While the above issue is "simple", it does beg the question of _when_ should the mode on a file descriptor be checked against the mode of the file object created by `open()`? In the case of built-in `open`, the answer appears to be "never", and instead the `file.flush()` can raise an `EBADF` `OSError` originating from the `write()` syscall. The following demonstrates the different behavior:

<details>
<summary>File handle mode mismatch tests</summary>

```python
def _do_test_bad_fdopen(base: Path):
    # Create a read-only handle to a read-only file
    f = base / "file.txt"
    fd = os.open(f, os.O_CREAT | os.O_RDONLY, 0b101_101_101)
    # Attempt to open a write stream to the underlying file
    out = open(fd, "wb")
    out.flush()  # Does not fail: The buffer is empty, so no write()

    # Fails: Tries to flush a non-empty buffer
    out.write(b"a")  # file.write() may fail by an implicit flush!
    with pytest.raises(OSError) as exc:
        out.flush()
    assert exc.value.errno == errno.EBADF

    # Fails: Tries to flush() again
    with pytest.raises(OSError) as exc:
        out.close()
    assert exc.value.errno == errno.EBADF

    out.close()  # Okay: The file is already closed
    f.unlink()


def test_realfs_bad(tmp_path: Path):
    _do_test_bad_fdopen(tmp_path)


def test_fakefs_bad(fs):
    _do_test_bad_fdopen(Path("/"))
```
</details>

These situations may be more difficult to handle, as it depends on buffering behavior and the timing of the underlying syscalls that can fail. I only tested the above on my Linux system. I suspect that macOS will behave similarly, but I'm unsure about Windows.

**Your environment**
Please run the following in the environment where the problem happened and
paste the output.
```bash
$ python -c "import platform; print(platform.platform())"
Linux-6.7.6-arch1-1-x86_64-with-glibc2.39
$ python -c "import sys; print('Python', sys.version)"
Python 3.11.7 (main, Jan 29 2024, 16:03:57) [GCC 13.2.1 20230801]
$ python -c "from pyfakefs import __version__; print('pyfakefs', __version__)"
pyfakefs 5.4.dev0
$ python -c "import pytest; print('pytest', pytest.__version__)"
pytest 7.2.0
```
