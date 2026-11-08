Filter is ignored on session resume
In cases we resume session and specify a filter, this filter is ignored during resume execution
```
def test_afail():
    raise ValueError

def test_bla1():
    pass

def test_bla2():
    pass
```

execution:
```
slash run -vv tests/test_bla.py -S -x
3 tests collected
[2020-09-16 20:27:40] Start Session: ebb806ca-f841-11ea-904c-644bf0016fa7_0
[2020-09-16 20:27:41] #1: tests/test_bla.py:test_afail
E: <Error: ValueError>, Test: <tests/test_bla.py:test_afail>
[2020-09-16 20:27:41] End Session: ebb806ca-f841-11ea-904c-644bf0016fa7_0
```

resume with filter:

```
slash resume -vv ebb806ca-f841-11ea-904c-644bf0016fa7_0 -S -k "not test_bla"
3 tests collected
[2020-09-16 20:30:28] Start Session: 4fb2c46c-f842-11ea-b7fe-644bf0016fa7_0
[2020-09-16 20:30:29] #1: tests/test_bla.py:test_afail
E: <Error: ValueError>, Test: <tests/test_bla.py:test_afail>
[2020-09-16 20:30:29] #2: tests/test_bla.py:test_bla1
[2020-09-16 20:30:29] #3: tests/test_bla.py:test_bla2
[2020-09-16 20:30:29] End Session: 4fb2c46c-f842-11ea-b7fe-644bf0016fa7_0
```
