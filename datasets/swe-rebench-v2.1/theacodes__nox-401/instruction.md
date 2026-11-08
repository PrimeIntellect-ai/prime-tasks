Selecting parameterized tests with CLI does not respect order of parameterize arguments
**Describe the bug**

When selecting parameterized tests with multiple parameters using the command line, the full session name does not respect the order of parameters. Instead, the arguments are ordered alphabetically.

[HIDDEN]

**How to reproduce**

1. Install nox in a python=3.7 environment.
2. Copy the following `noxfile.py` to a test folder.
```python
import nox

@nox.session(venv_backend="conda")
@nox.parametrize(
    ("a", "c", "b"),
    [
        ("a1", "c1", "b1"),
        ("a1", "c1", "b2"),
        ("a1", "c2", "b1"),
        ("a1", "c2", "b2"),
        ("a2", "c1", "b1"),
        ("a2", "c1", "b2"),
        ("a2", "c2", "b1"),
        ("a2", "c2", "b2"),
    ],
)
def test(session, a, b, c):
     print(f"running a={a}, b={b}, c={c}")
```
3. Run `nox --list`  or `nox` to observe the name of the sessions. Sample output is below.

**Expected behavior**

The session names should have arguments in the same order as in the parameterize call, ie `test(a="a1", c="c1", b="b1")`. Instead, they are run in alphabetical order.

Output of `nox --list`:
```
Sessions defined in /nox_bug_report/noxfile.py:

* test(a='a1', b='b1', c='c1')
* test(a='a1', b='b2', c='c1')
* test(a='a1', b='b1', c='c2')
* test(a='a1', b='b2', c='c2')
* test(a='a2', b='b1', c='c1')
* test(a='a2', b='b2', c='c1')
* test(a='a2', b='b1', c='c2')
* test(a='a2', b='b2', c='c2')

sessions marked with * are selected, sessions marked with - are skipped.
```

Output of `nox`:
```
nox > Running session test(a='a1', b='b1', c='c1')
nox > Creating conda env in .nox/test-a-a1-b-b1-c-c1 with python
running a=a1, b=b1, c=c1
nox > Session test(a='a1', b='b1', c='c1') was successful.
nox > Running session test(a='a1', b='b2', c='c1')
nox > Creating conda env in .nox/test-a-a1-b-b2-c-c1 with python
running a=a1, b=b2, c=c1
nox > Session test(a='a1', b='b2', c='c1') was successful.
nox > Running session test(a='a1', b='b1', c='c2')
nox > Creating conda env in .nox/test-a-a1-b-b1-c-c2 with python
running a=a1, b=b1, c=c2
nox > Session test(a='a1', b='b1', c='c2') was successful.
nox > Running session test(a='a1', b='b2', c='c2')
nox > Creating conda env in .nox/test-a-a1-b-b2-c-c2 with python
running a=a1, b=b2, c=c2
nox > Session test(a='a1', b='b2', c='c2') was successful.
nox > Running session test(a='a2', b='b1', c='c1')
nox > Creating conda env in .nox/test-a-a2-b-b1-c-c1 with python
running a=a2, b=b1, c=c1
nox > Session test(a='a2', b='b1', c='c1') was successful.
nox > Running session test(a='a2', b='b2', c='c1')
nox > Creating conda env in .nox/test-a-a2-b-b2-c-c1 with python
running a=a2, b=b2, c=c1
nox > Session test(a='a2', b='b2', c='c1') was successful.
nox > Running session test(a='a2', b='b1', c='c2')
nox > Creating conda env in .nox/test-a-a2-b-b1-c-c2 with python
running a=a2, b=b1, c=c2
nox > Session test(a='a2', b='b1', c='c2') was successful.
nox > Running session test(a='a2', b='b2', c='c2')
nox > Creating conda env in .nox/test-a-a2-b-b2-c-c2 with python
running a=a2, b=b2, c=c2
nox > Session test(a='a2', b='b2', c='c2') was successful.
nox > Ran multiple sessions:
nox > * test(a='a1', b='b1', c='c1'): success
nox > * test(a='a1', b='b2', c='c1'): success
nox > * test(a='a1', b='b1', c='c2'): success
nox > * test(a='a1', b='b2', c='c2'): success
nox > * test(a='a2', b='b1', c='c1'): success
nox > * test(a='a2', b='b2', c='c1'): success
nox > * test(a='a2', b='b1', c='c2'): success
nox > * test(a='a2', b='b2', c='c2'): success
```
