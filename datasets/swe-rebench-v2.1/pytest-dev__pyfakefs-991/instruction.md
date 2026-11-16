Faked `os.makedirs` differs from the built-in `os.makedirs` and `mkdir -p`
**Describe the bug**
> This issue comes with some bonus cursed knowledge.

`os.makedirs` and `mkdir -p` both do a "weird" thing when they create directory trees:

```console
$ mkdir -p base/foo/../bar
# ls base
bar/  foo/
```

That is:
1. It creates `base/` if absent, then enters `base/`
2. Create `foo/` if absent, then enter `foo/`
3. It creates `../` if absent (it is never absent on "normal" filesystems), then enters `../` (sending it back into `base/`)
4. Then creates `bar/`

(`os.makedirs` does the same thing.)

`pyfakefs`'s `os.makedirs` normalizes the path before it does the above process, meaning the `foo` and `..` parts will be chopped out of the path, and the `foo/` directory will not be created.

**How To Reproduce**
```python
def weird_makedirs(base: Path):
    shutil.rmtree(base, ignore_errors=True)
    b = base / "foo/../bar"
    os.makedirs(b)
    assert (base / "bar").is_dir()
    assert (base / "foo").is_dir()
    assert not (base / "foo/bar").is_dir()

def test_weird_makedirs_realfs():
    weird_makedirs(Path("testdir-tmp"))

def test_weird_makedirs_fakefs(fs):
    weird_makedirs(Path("testdir-tmp"))
```

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
