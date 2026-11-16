`PureWindowsPath.stem` changes behavior when `fs` fixture is loaded
**Describe the bug**

When the `fs` fixture is loaded, `pathlib.PureWindowsPath.stem` returns more than the file's stem.


**How To Reproduce**

```bash
mkdir demo
cd demo
python -m venv .venv
source .venv/bin/activate
pip install pytest pyfakefs
```

Create a file named `test_demo.py` with this content:

```python
import pathlib

def test_basic():
    assert pathlib.PureWindowsPath(r"C:\example\demo.py").stem == "demo"

def test_pyfakefs(fs):
    assert pathlib.PureWindowsPath(r"C:\example\demo.py").stem == "demo"
```

Then run:

```bash
pytest test_demo.py
```

You will see the following output:

```
$ pytest test_demo.py
============================== test session starts ===============================
platform linux -- Python 3.12.3, pytest-8.2.0, pluggy-1.5.0
rootdir: /home/kurt/dev/test
configfile: pyproject.toml
plugins: pyfakefs-5.4.1
collected 2 items

test_demo.py .F                                                            [100%]

==================================== FAILURES ====================================
_________________________________ test_pyfakefs __________________________________

fs = <pyfakefs.fake_filesystem.FakeFilesystem object at 0x7dec1ffc4e90>

    def test_pyfakefs(fs):
>       assert pathlib.PureWindowsPath(r"C:\example\demo.py").stem == "demo"
E       AssertionError: assert 'C:\\example\\demo' == 'demo'
E
E         - demo
E         + C:\example\demo

/home/kurt/dev/test/test_demo.py:8: AssertionError
============================ short test summary info =============================
FAILED test_demo.py::test_pyfakefs - AssertionError: assert 'C:\\example\\demo' == 'demo'
========================== 1 failed, 1 passed in 0.08s ===========================
```

**Your environment**
```
Linux-6.5.0-28-generic-x86_64-with-glibc2.35
Python 3.12.3 (main, Apr 10 2024, 14:08:50) [GCC 11.4.0]
pyfakefs 5.4.1
pytest 8.2.0
```
