Patched `os.symlink` mishandles directory descriptors
**Describe the bug**
The `os.symlink` function accepts a `dir_fd` argument to specify the destination of the created symlink. The fakefs `os.symlink` is behaves incorrectly and uses the `dir_fd` to rewrite the `src` argument:

```python
[HIDDEN]
```

[HIDDEN]

The doc comment is written to reflect the incorrect behavior.

**How To Reproduce**
```python
def _test_symlink(base: Path):
    dir_fd = os.open(base, os.O_DIRECTORY)
    os.symlink("file.txt", "link.txt", dir_fd=dir_fd)
    assert os.readlink(base / "link.txt") == "file.txt"

def test_symlink_realfs(tmp_path: Path):
    _test_symlink(tmp_path)

def test_symlink_fakefs(fs):
    _test_symlink(Path("/tmp/"))
```

The `os.symlink` call above will succeed, but creates `link.txt` in the wrong location, leading to  `os.readlink` generating a `FileNotFoundError`.

**Your environment**
Please run the following in the environment where the problem happened and
paste the output.
```console
$ python -c "import platform; print(platform.platform())"
Linux-6.7.6-arch1-1-x86_64-with-glibc2.39
$ python -c "import sys; print('Python', sys.version)"
Python 3.11.7 (main, Jan 29 2024, 16:03:57) [GCC 13.2.1 20230801]
$ python -c "from pyfakefs import __version__; print('pyfakefs', __version__)"
pyfakefs 5.4.dev0
$ python -c "import pytest; print('pytest', pytest.__version__)"
pytest 7.2.0
```

### Additional contract requirements

- For fake `os.symlink`, a relative destination must be created relative to the directory identified by `dir_fd`.
- The symlink target must be preserved as supplied; `dir_fd` must not change the value returned by `os.readlink` for that link.
