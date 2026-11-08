@attr.define fails to auto-detect __eq__
`@attr.define` is failing to auto-detect `__eq__`. My understanding from the docs is that this _should_ work, but `ValueError` is not being raised unless I use `@attr.define(eq=False)`.

```python
import attr

@attr.define
class Treatment:
    treatment: str

    def __eq__(self, other):
        raise ValueError


assert Treatment("foo") == "foo"
```

```console
$ pytest t.py
================================ test session starts ================================
platform darwin -- Python 3.8.5, pytest-6.0.1, py-1.8.2, pluggy-0.13.1
rootdir: /Users/andy/tmp
plugins: Faker-4.1.1
collected 0 items / 1 error

====================================== ERRORS =======================================
_______________________________ ERROR collecting t.py _______________________________
t.py:11: in <module>
    assert Treatment("foo") == "foo"
E   AssertionError: assert Treatment(treatment='foo') == 'foo'
E    +  where Treatment(treatment='foo') = <class 't.Treatment'>('foo')
============================== short test summary info ==============================
ERROR t.py - AssertionError: assert Treatment(treatment='foo') == 'foo'
!!!!!!!!!!!!!!!!!!!!!! Interrupted: 1 error during collection !!!!!!!!!!!!!!!!!!!!!!!
```
