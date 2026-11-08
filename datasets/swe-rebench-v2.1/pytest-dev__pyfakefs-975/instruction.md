Faked `os.link` is missing the `follow_symlinks` parameter
**Describe the bug**
Pretty much what it says on the tin.

**How To Reproduce**
```python
def link_nofollow(s: Path, d: Path):
    s.unlink(missing_ok=True)
    d.unlink(missing_ok=True)
    s.symlink_to("nowhere")
    os.link(s, d, follow_symlinks=False)
    assert os.readlink(d) == "nowhere"

def test_realfs():
    link_nofollow(Path("file.txt"), Path("another.txt"))

def test_fakefs(fs):
    link_nofollow(Path("file.txt"), Path("another.txt"))
```

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

- `os.link` accepts an optional `follow_symlinks` argument. When it is `True` or omitted, symlinks in the source path are traversed and the hard link is created to the link target. When it is `False`, the hard link is created to the symlink itself.
