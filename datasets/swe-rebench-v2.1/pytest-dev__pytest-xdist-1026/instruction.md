Session-scoped fixture executed too many times with `-x` / `--maxfails`
This is related, but I think slightly different than #868 and #420 (which deals with the fact that these flags do not stop execution after a fail).

Observe this test file:
```python
import sys
from time import sleep

from pytest import fixture

# hack for live prints (https://stackoverflow.com/questions/27006884)
sys.stdout = sys.stderr


@fixture(scope='session', autouse=True)
def session_fixture():
    print('### executing fixture! ###')


def test_1():
    assert False


def test_2():
    sleep(1)


def test_3():
    sleep(1)


def test_4():
    sleep(1)
```

Running this with:
```
pytest test_parallel.py  -n 2  -s --maxfail=1
```

leads to the `session_fixture` being executed 3 times!   Removing `--maxfail=1`, you can see `session_fixture` is executed twice (as expected).

### Additional contract requirements

With `--maxfail=1` and two workers (`-n 2`), the session-scoped fixture must be
executed exactly twice (once per worker), the same as when `--maxfail` is not
given. It must not be executed a third time.
