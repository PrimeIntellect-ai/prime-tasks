Cannot decode subclass of exception with keyword parameter
I am using jsonpickle v4.1.1.

I am likely doing something dumb, but I am getting an error when trying to decode into a subclass of Exception with one keyword only argument. I can minimally reproduce this as follows:

```py
import jsonpickle

class Foo(Exception):
    def __init__(self, a, *, b):
        self.a = a
        self.b = b

>>> jsonpickle.encode(Foo("a", b="b"))
'{"py/reduce": [{"py/type": "__main__.Foo"}, {"py/tuple": ["a"]}, {"a": "a", "b": "b"}]}'

>>> jsonpickle.decode(jsonpickle.encode(Foo("a", b="b")))
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/Users/dfarr/Developer/resonatehq-examples/deep-research/.venv/lib/python3.12/site-packages/jsonpickle/unpickler.py", line 103, in decode
    return context.restore(data, reset=reset, classes=classes)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/dfarr/Developer/resonatehq-examples/deep-research/.venv/lib/python3.12/site-packages/jsonpickle/unpickler.py", line 420, in restore
    value = self._restore(obj)
            ^^^^^^^^^^^^^^^^^^
  File "/Users/dfarr/Developer/resonatehq-examples/deep-research/.venv/lib/python3.12/site-packages/jsonpickle/unpickler.py", line 402, in _restore
    return restore(obj)
           ^^^^^^^^^^^^
  File "/Users/dfarr/Developer/resonatehq-examples/deep-research/.venv/lib/python3.12/site-packages/jsonpickle/unpickler.py", line 555, in _restore_reduce
    stage1 = f(*args)
             ^^^^^^^^
TypeError: Foo.__init__() missing 1 required keyword-only argument: 'b'
```

I also get a similar error when Foo is defined with two positional arguments and I instantiate as `Foo("a", b="b")`. However, I do not get this error if I instantiate with two positional args in this case `Foo("a", "b")`

### Additional contract requirements

- An encode/decode round trip must preserve the value of an exception instance's `c` attribute.
